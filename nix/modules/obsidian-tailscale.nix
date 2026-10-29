{ config, pkgs, ... }:

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
#
# Path:  tailscaled :443  ->  127.0.0.1:15984 (couchdb-local-proxy)
#                         ->  10.43.20.9:5984 (couchdb ClusterIP, kube-proxy)
#
# The localhost hop is required: tailscale 1.90 serve rejects any other
# backend ("only localhost or 127.0.0.1 proxies are currently supported").
# The plaintext tail stays on lh-satellite: the proxy binds loopback only and
# the Service has no NodePort and no Ingress.
#
# Backend coupling: 10.43.20.9:5984 is the fixed clusterIP of the `couchdb`
# Service in gitops/apps/obsidian-sync/deploy.yaml. Change both together.

let
  localPort = 15984;
  couchdb = "10.43.20.9:5984";
in
{
  # Socket-activated TCP forwarder (systemd's own, no extra package). The
  # socket is always listening; the proxy process starts on first connection.
  systemd.sockets.couchdb-local-proxy = {
    description = "Loopback listener for CouchDB (Obsidian LiveSync)";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "127.0.0.1:${toString localPort}" ];
  };

  systemd.services.couchdb-local-proxy = {
    description = "Forward 127.0.0.1:${toString localPort} to the CouchDB ClusterIP";
    requires = [ "couchdb-local-proxy.socket" ];
    after = [ "couchdb-local-proxy.socket" ];
    serviceConfig = {
      ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${couchdb}";
      DynamicUser = true;
    };
  };

  systemd.services.tailscale-serve-obsidian = {
    description = "Tailscale serve for Obsidian LiveSync (CouchDB)";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" "couchdb-local-proxy.socket" ];
    wants = [ "tailscaled.service" "couchdb-local-proxy.socket" ];
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
      tailscale serve --bg --https=443 http://127.0.0.1:${toString localPort}
    '';
  };
}
