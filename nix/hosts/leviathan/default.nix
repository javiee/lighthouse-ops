{ hostname, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/common.nix
    ../../modules/workstation.nix
    ../../modules/ssh.nix
    ../../modules/users.nix
    ../../modules/tailscale.nix
    ../../modules/nvidia.nix
    ../../modules/ollama.nix
    ../../modules/llama-cpp.nix
    ../../modules/k3s-join.nix
  ];

  networking.hostName = hostname;

  system.stateVersion = "25.11";
}
