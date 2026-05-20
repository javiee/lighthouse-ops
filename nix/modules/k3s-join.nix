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
    serverAddr = "https://192.168.10.122:6443";
    tokenFile = config.age.secrets.k3s-token.path;
  };

  # Agent ports:
  #   10250 = kubelet (API server proxy: logs, exec, port-forward)
  #    9100 = prometheus-node-exporter (host metrics)
  #    9400 = nvidia dcgm-exporter (GPU metrics)
  #    8472 = flannel VXLAN (pod-to-pod overlay)
  networking.firewall.allowedTCPPorts = [ 10250 9100 9400 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  environment.systemPackages = with pkgs; [
    k3s
    kubectl
  ];
}

