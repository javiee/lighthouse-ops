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
    ../../modules/llama-swap.nix
  ];

  networking.hostName = hostname;

  # Allow llama-server to pin model weights + KV cache in RAM (no swap).
  security.pam.loginLimits = [
    { domain = "*"; item = "memlock"; type = "soft"; value = "unlimited"; }
    { domain = "*"; item = "memlock"; type = "hard"; value = "unlimited"; }
  ];

  system.stateVersion = "25.11";
}
