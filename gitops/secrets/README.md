# Encrypted Kubernetes secrets (SOPS + age)

This directory holds **all** cluster Secrets for this repo's GitOps workloads,
committed **encrypted** with [SOPS](https://github.com/getsops/sops) +
[age](https://age-encryption.org/). Flux decrypts them at reconcile time
(kustomize-controller, `secrets` Kustomization in `gitops/lighthouse-cluster/secrets.yaml`);
no secrets are ever applied by hand.

## Layout

```
.sops.yaml                          (repo root — creation rules + age public key)
gitops/secrets/
├── README.md                 (this file)
├── hermes-agent/
│   ├── hermes-dashboard-auth.sops.yaml
│   ├── hermes-github-token.sops.yaml
│   └── hermes-hass-token.sops.yaml
├── obsidian-sync/
│   └── couchdb-admin.sops.yaml
└── <namespace>/<secret-name>.sops.yaml
```

One file per Secret; the directory is the namespace, the file is the Secret
name. Only `*.sops.yaml` and `README.md` may live here — the pre-commit hook
refuses anything else, and gitleaks refuses plaintext `data`/`stringData`.

## Keys (never in git)

- **age public key** — committed, in `.sops.yaml` (repo root). Safe to share.
- **age private key** — `~/.config/sops/age/key-lighthouse.txt` on the laptop,
  **backed up in the password manager**. Losing both = every secret in this
  cluster is unrecoverable until rotated.
- **`sops-age` Secret in `flux-system`** — the private key for the cluster.
  Created out-of-band (see "Bootstrapping a new cluster" below). Never in git.

## Day-2 workflows

Run all `sops` commands **from the repo root, inside the devshell** (`nix
develop` / direnv — the devshell exports `SOPS_AGE_KEY_FILE`; outside it, set
that env var to the private key path manually).

### Create a new Secret

```bash
# 1. Draft in plaintext OUTSIDE the repo (never inside git/).
D=$(mktemp -d)
cat > "$D/my-secret.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
stringData:
  MY_KEY: value-here
EOF

# 2. Encrypt in place at its final path.
mkdir -p gitops/secrets/my-namespace
cp "$D/my-secret.yaml" gitops/secrets/my-namespace/my-secret.sops.yaml
sops -e --in-place gitops/secrets/my-namespace/my-secret.sops.yaml

# 3. Sanity-check: values must be ciphertext now.
sops -d gitops/secrets/my-namespace/my-secret.sops.yaml | jq .stringData   # prints values — be careful
rm -rf "$D"

# 4. Reference it in the chart/manifest (secretEnv / valueFrom.secretKeyRef).
# 5. git add gitops/secrets/my-namespace/my-secret.sops.yaml → commit → push.
#    Flux picks it up within ~1 minute (Kustomization `secrets`).
```

### Edit / rotate an existing value

```bash
sops -d gitops/secrets/<ns>/<name>.sops.yaml > "$TMPDIR/scratch.yaml"   # OUTSIDE git/
# edit $TMPDIR/scratch.yaml
cp "$TMPDIR/scratch.yaml" gitops/secrets/<ns>/<name>.sops.yaml
sops -e --in-place gitops/secrets/<ns>/<name>.sops.yaml
rm "$TMPDIR/scratch.yaml"
# commit + push; then restart consumers if the env vars matter:
kubectl rollout restart deployment/<name> -n <ns>
```

### Read a value (troubleshooting)

```bash
sops -d gitops/secrets/<ns>/<name>.sops.yaml | yq '.stringData'
```

### Add a second recipient (new machine/person)

Generate their age keypair (`age-keygen`), add their public key as a
**second entry** under `age:` in `.sops.yaml` (same keygroup = both can
decrypt), then re-encrypt each file so the new key lands in its metadata:

```bash
f=gitops/secrets/<ns>/<name>.sops.yaml
sops -d "$f" > "$TMPDIR/rekey.yaml"
cp "$TMPDIR/rekey.yaml" "$f"
sops -e --in-place "$f"
rm "$TMPDIR/rekey.yaml"
```

Remove recipients the same way (drop the line, re-encrypt).

## "I forgot to encrypt" trap

If you ever drop a plaintext Secret manifest into `gitops/secrets/`:

1. The pre-commit hook **will** block it (name guard + gitleaks rule).
2. If it still slips in (e.g. `--no-verify`), treat the value as compromised:
   rotate it, and purge it with `git filter-repo` — it is in git history.

## Bootstrapping a new cluster (or replacing `sops-age`)

```bash
kubectl -n flux-system create secret generic sops-age \
  --from-file age.agekey=$HOME/.config/sops/age/key-lighthouse.txt
```

The data key **must** end in `.agekey` — kustomize-controller imports age
identities from `sops-age` data keys by that extension only (any key name
with the suffix works; `age.agekey` is the convention).

Then Flux's `secrets` Kustomization decrypts and applies everything; the
app Kustomizations `dependsOn: [secrets]` so workloads start afterwards.
