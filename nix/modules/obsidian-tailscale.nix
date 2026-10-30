{ pkgs, ... }:

# Expose the CouchDB backing Obsidian LiveSync over HTTPS on the tailnet.
#
# The pinned nixpkgs (25.11) tailscale module has no `serve` option, so the
# serve config is applied with a oneshot unit. Re-applying an identical
# config is a no-op, so the unit is safe to run on every boot.
#
# tailscale serve (1.90) only proxies to localhost/127.0.0.1 backends, so a
# loopback socat bridge (couchdb-bridge) forwards 127.0.0.1:15984 to the
# pinned CouchDB ClusterIP. The bridge binds loopback only, so the ClusterIP
# stays node-local (the Service has no NodePort and no Ingress).
#
# TLS terminates inside tailscaled with a cert for
# lh-satellite.tail8c42d8.ts.net (tailnet-embedded CA, auto-renewed).
#
# Backend coupling: 10.43.20.9:5984 is the fixed clusterIP of the `couchdb`
# Service in gitops/apps/obsidian-sync/deploy.yaml. Change both together.

{
  systemd.services.couchdb-bridge = {
    description = "Loopback bridge 127.0.0.1:15984 -> CouchDB ClusterIP 10.43.20.9:5984";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" ];
    path = [ pkgs.socat ];
    serviceConfig = {
      ExecStart =
        "${pkgs.socat}/bin/socat TCP-LISTEN:15984,bind=127.0.0.1,reuseaddr,fork TCP:10.43.20.9:5984";
      Restart = "on-failure";
    };
  };

  systemd.services.tailscale-serve-obsidian = {
    description = "Tailscale serve for Obsidian LiveSync (CouchDB)";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" "couchdb-bridge.service" ];
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
        if tailscale status >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      tailscale serve --bg --https=443 http://127.0.0.1:15984
    '';
  };
}
