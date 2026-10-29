#!/usr/bin/env bash
# Create/replace the out-of-band `couchdb-admin` Secret for Obsidian LiveSync
# and restart CouchDB. Run from the Mac:
#
#   gitops/apps/obsidian-sync/set-admin-secret.sh
#
# The password is generated ON lh-satellite and kept in
# ~/couchdb-admin-password there (mode 600). It is never printed; an existing
# file is reused, so re-running is safe. Read it later for the LiveSync setup:
#
#   ssh jcaro@lh-satellite cat ~/couchdb-admin-password
#
# Alphanumeric only: it ends up inside LiveSync's setup URI.
# (lh-satellite has no openssl, hence /dev/urandom.)
set -euo pipefail

HOST="${1:-jcaro@lh-satellite}"

ssh "$HOST" bash -s <<'REMOTE'
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
umask 077

f="$HOME/couchdb-admin-password"
if [ ! -s "$f" ]; then
  # head closes the pipe early, so tr exits on SIGPIPE; ignore that status.
  (tr -dc 'A-Za-z0-9' < /dev/urandom || true) | head -c 32 > "$f"
  echo "generated new password in $f"
else
  echo "reusing existing password in $f"
fi

kubectl -n obsidian-sync create secret generic couchdb-admin \
  --from-literal=COUCHDB_USER=admin \
  --from-file=COUCHDB_PASSWORD="$f" \
  --dry-run=client -o yaml | kubectl apply -f -

len=$(kubectl -n obsidian-sync get secret couchdb-admin \
  -o jsonpath='{.data.COUCHDB_PASSWORD}' | base64 -d | wc -c)
echo "password length in secret: $len"
[ "$len" -ge 16 ] || { echo "ERROR: password too short/empty" >&2; exit 1; }

kubectl -n obsidian-sync rollout restart deploy/couchdb
kubectl -n obsidian-sync rollout status deploy/couchdb --timeout=150s
REMOTE
