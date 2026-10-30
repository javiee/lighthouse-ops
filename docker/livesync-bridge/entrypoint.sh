#!/bin/sh
# Builds the bridge config from env (credentials come from a k8s Secret, so no
# config file with a password is baked or mounted), waits for the LiveSync
# database to be initialised by the Obsidian plugin, then starts the bridge.
#
#   COUCHDB_URL, COUCHDB_USER, COUCHDB_PASSWORD   required
#   LIVESYNC_DATABASE                             required (plugin's "Database name")
#   LIVESYNC_VAULT_DIR                            required, absolute
#   LIVESYNC_PASSPHRASE                           E2EE passphrase, empty if E2EE is off
#   LIVESYNC_OBFUSCATE_PASSPHRASE                 path obfuscation passphrase, empty if off
#   LIVESYNC_ID_KEY                               "Show current recovery code" value, if any
#   LSB_STATE_DIR                                 persistent dir for resume checkpoints
#                                                 (Deno localStorage); ephemeral if unset
set -eu

if [ -z "${COUCHDB_USER:-}" ] || [ -z "${COUCHDB_PASSWORD:-}" ]; then
  # Secret not created yet: idle instead of crash-looping the pod. Env is read
  # at container start, so restart the pod after creating it.
  echo "[lsb-entrypoint] COUCHDB_USER/COUCHDB_PASSWORD not set; bridge idle" >&2
  exec sleep infinity
fi

export LSB_CONFIG="${LSB_CONFIG:-/tmp/lsb-config.json}"
mkdir -p "$LIVESYNC_VAULT_DIR"

# Deno keeps localStorage under $DENO_DIR/location_data, which also holds the
# deps baked into the image, so only that one subdirectory is redirected.
if [ -n "${LSB_STATE_DIR:-}" ]; then
  mkdir -p "$LSB_STATE_DIR"
  rm -rf /deno-dir/location_data
  ln -s "$LSB_STATE_DIR" /deno-dir/location_data
fi

deno eval '
const e = (k, d) => { const v = Deno.env.get(k); if (v === undefined && d === undefined) throw new Error(`${k} is not set`); return v ?? d; };
const couchdb = {
  type: "couchdb", name: "couchdb", group: "vault",
  url: e("COUCHDB_URL"), database: e("LIVESYNC_DATABASE"),
  username: e("COUCHDB_USER"), password: e("COUCHDB_PASSWORD"),
  passphrase: e("LIVESYNC_PASSPHRASE", ""),
  obfuscatePassphrase: e("LIVESYNC_OBFUSCATE_PASSPHRASE", ""),
  baseDir: "", useRemoteTweaks: true,
};
const idKey = e("LIVESYNC_ID_KEY", "");
if (idKey) couchdb.idDerivationKey = idKey;
const storage = {
  type: "storage", name: "vault", group: "vault",
  baseDir: e("LIVESYNC_VAULT_DIR").replace(/\/*$/, "/"),
  scanOfflineChanges: true,
  ignore: ["**/.git/**", ".trash/**"],
};
await Deno.writeTextFile(Deno.env.get("LSB_CONFIG"), JSON.stringify({ peers: [couchdb, storage] }), { mode: 0o600 });
'

# Don't let the bridge create the database: the plugin must initialise it first
# (it writes the milestone doc carrying chunk size / E2EE tweaks that
# useRemoteTweaks reads). Until then the vault folder just stays empty.
deno eval '
const url = `${Deno.env.get("COUCHDB_URL")}/${Deno.env.get("LIVESYNC_DATABASE")}/_local/obsydian_livesync_milestone`;
const auth = "Basic " + btoa(`${Deno.env.get("COUCHDB_USER")}:${Deno.env.get("COUCHDB_PASSWORD")}`);
for (let i = 0; ; i++) {
  try {
    const r = await fetch(url, { headers: { authorization: auth } });
    await r.body?.cancel();
    if (r.ok) break;
    if (i % 20 === 0) console.log(`[lsb-entrypoint] waiting for LiveSync database (HTTP ${r.status})`);
  } catch (err) {
    if (i % 20 === 0) console.log(`[lsb-entrypoint] waiting for CouchDB: ${err.message}`);
  }
  await new Promise((r) => setTimeout(r, 30_000));
}
'

exec deno task run
