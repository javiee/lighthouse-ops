{ config, pkgs, ... }:

# Node that joins an existing k3s cluster.
# Set `serverAddr` to the first server's URL (use its tailscale IP/MagicDNS name).
# Choose role:
#   "server" → HA control plane (adds to embedded-etcd; need 3 total for fault tolerance)
#   "agent"  → worker only (lighter weight)

{
  age.secrets.k3s-token.file = ../../secrets/k3s-token.age;

  services.k3s = {
    enable = true;
    role = "agent";  # or "server" for HA
    serverAddr = "https://CHANGE_ME:6443";
    tokenFile = config.age.secrets.k3s-token.path;
    extraFlags = [
      "--flannel-iface=tailscale0"
    ];
  };

  systemd.services.k3s = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  # Agent needs kubelet (10250) and flannel (8472/udp). Servers additionally need 6443 + etcd ports.
  networking.firewall.allowedTCPPorts = [ 10250 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  environment.systemPackages = with pkgs; [
    k3s
    kubectl
  ];
}
