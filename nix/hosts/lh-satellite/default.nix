{ hostname, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/common.nix
    ../../modules/workstation.nix
    ../../modules/ssh.nix
    ../../modules/users.nix
    ../../modules/tailscale.nix
    ../../modules/k3s-bootstrap.nix
    ../../modules/flux-bootstrap.nix
  ];

  networking.hostName = hostname;

  system.stateVersion = "25.11";
}
