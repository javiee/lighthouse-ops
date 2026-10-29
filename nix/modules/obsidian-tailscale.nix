{ pkgs, ... }:

# Expose the CouchDB backing Obsidian LiveSync over HTTPS on the tailnet.
#
# The pinned nixpkgs (25.11) tailscale module has no `serve` option, so the
# serve config is applied with a oneshot unit. Re-applying an identical
# config is a no-op, so the unit is safe to run on every boot.
#
# TLS terminates inside tailscaled with a cert for
# lh-satellite.tail8c42d8.ts.net (tailnet-embedded CA, auto-renewed).
# The plaintext tail to the pinned CouchDB ClusterIP stays node-local
# (the Service has no NodePort and no Ingress).
#
# Backend coupling: 10.43.20.9:5984 is the fixed clusterIP of the `couchdb`
# Service in gitops/apps/obsidian-sync/deploy.yaml. Change both together.

{
  systemd.services.tailscale-serve-obsidian = {
    description = "Tailscale serve for Obsidian LiveSync (CouchDB)";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.tailscale ];
    script = ''
      set -euo pipefail

      # Wait for tailscaled to be running before applying the serve config.
      for i in $(seq 1 30); do
        if tailscale status 2>/dev/null | grep -q "Online"; then
          break
        fi
        sleep 5
      done

      tailscale serve --bg --https=443 tcp://10.43.20.9:5984
    '';
  };
}
