# livesync-bridge (vrtmrz) — replicates a Self-hosted LiveSync CouchDB vault to
# a plain folder of .md files and back. Runs as a sidecar of hermes-agent so the
# Obsidian skill (filesystem-only, OBSIDIAN_VAULT_PATH) can read the vault.
#
# Upstream publishes no image, only a Dockerfile; this is the same build pinned
# to a commit and run as UID 10000 (hermes' UID) so both containers can write
# the shared vault folder on the PVC.
FROM docker.io/denoland/deno:2.9.7

ARG LSB_COMMIT=06327188abd4488410882a3e2705471f2477af8e

USER root
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    git clone https://github.com/vrtmrz/livesync-bridge /app && \
    git -C /app checkout "$LSB_COMMIT" && \
    rm -rf /app/.git && \
    apt-get purge -y git && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN deno install --frozen

COPY --chmod=0755 entrypoint.sh /usr/local/bin/lsb-entrypoint
RUN chown -R 10000:10000 /app /deno-dir

USER 10000:10000
ENTRYPOINT [ "/usr/local/bin/lsb-entrypoint" ]
