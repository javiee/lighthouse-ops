{ pkgs, ... }:

# Expose the CouchDB backing Obsidian LiveSync over HTTPS on the tailnet.
#
# The pinned nixpkgs (25.11) tailscale module has no `serve` option, so the
# serve config is applied with a oneshot unit. Re-applying an identical
# config is a no-op, so the unit is safe to run on every boot.
#
# TLS terminates inside tailscaled with a Let's Encrypt cert for
# lh-satellite.tail8c42d8.ts.net (auto-renewed). Needs Serve + HTTPS
# Certificates enabled once for the tailnet in the admin console (done
# 2026-10-29); until then `tailscale serve` blocks waiting for approval.
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
      # `tailscale serve` waits indefinitely for admin approval when Serve is
      # not enabled on the tailnet — and an unbounded oneshot also stalls
      # `nixos-rebuild switch`. Fail instead; the journal has the approval URL.
      TimeoutStartSec = "2min";
    };
    path = [ pkgs.tailscale ];
    script = ''
      set -euo pipefail

      # tailscaled is up before it is logged in; serve fails until then.
      # (`tailscale status` text never contains "Online" — check the JSON.)
      for _ in $(seq 1 30); do
        if tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
          break
        fi
        sleep 2
      done

      # --https is an HTTP reverse proxy: the target must be http(s)://.
      # (tcp:// targets are only for --tcp / --tls-terminated-tcp.)
      tailscale serve --bg --https=443 http://10.43.20.9:5984
    '';
  };
}
