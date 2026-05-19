{ config, pkgs, ... }:

# First node of the cluster: initialises the embedded-etcd datastore.
# Only ONE node in the cluster should import this module.
# All subsequent nodes should import ./k3s-join.nix instead.

{
  age.secrets.k3s-token.file = ../../secrets/k3s-token.age;

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    tokenFile = config.age.secrets.k3s-token.path;
    extraFlags = [
        "--write-kubeconfig-mode=0640"
        "--write-kubeconfig-group=kubeconfig"
        "--node-ip=192.168.10.122"
        "--advertise-address=192.168.10.122"
      # "--tls-san=<tailscale-hostname-or-dns>"
    ];
  };

  systemd.services.k3s = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  # Server ports:
  #     80/443 = traefik ingress
  #       6443 = kube API server
  #      10250 = kubelet
  #       9100 = prometheus-node-exporter (host metrics)
  #  2379-2380 = etcd (client + peer)
  #       8472 = flannel VXLAN (pod-to-pod overlay)
  networking.firewall.allowedTCPPorts = [ 80 443 6443 10250 9100 2379 2380 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  users.groups.kubeconfig = {};

  users.users.jcaro = {
    isNormalUser = true;
    extraGroups = [ "kubeconfig" ];
  };

  environment.systemPackages = with pkgs; [
    k3s
    kubectl
    etcd
    fluxcd
  ];
}
