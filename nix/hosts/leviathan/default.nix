{ hostname, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/common.nix
    ../../modules/workstation.nix
    ../../modules/ssh.nix
    ../../modules/users.nix
    ../../modules/tailscale.nix
    ../../modules/amdgpu.nix
    ../../modules/llama-cpp.nix
    ../../modules/k3s-join.nix
    ../../modules/llama-swap.nix
    ../../modules/lemonade.nix
  ];

  networking.hostName = hostname;

  # Per-user ssh-agent (systemd user unit) with SSH_AUTH_SOCK exported in
  # every login shell, so `ssh-add` works and keys persist across sessions.
  # ~/.ssh/config has `AddKeysToAgent yes`, so the first use loads the key.
  programs.ssh.startAgent = true;

  # Allow llama-server to pin model weights + KV cache in RAM (no swap).
  security.pam.loginLimits = [
    { domain = "*"; item = "memlock"; type = "soft"; value = "unlimited"; }
    { domain = "*"; item = "memlock"; type = "hard"; value = "unlimited"; }
  ];

  system.stateVersion = "25.11";
}
