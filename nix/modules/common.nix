{ pkgs, opencode, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Let admins pass privileged nix options (extra-substituters,
  # extra-trusted-public-keys, stalled-download-timeout) from the command line.
  # An untrusted user's --option for these is silently IGNORED by the daemon,
  # which shows up as "why is it rebuilding everything from source".
  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Safety net: a real kernel panic should reboot and self-heal, not hang.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;          # reboot 10s after a panic
    "kernel.panic_on_oops" = 1;   # treat an oops as a panic
    # "vm.panic_on_oom" = 1;      # would panic on OOM instead of killing a process
  };

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_ES.UTF-8";
    LC_IDENTIFICATION = "es_ES.UTF-8";
    LC_MEASUREMENT = "es_ES.UTF-8";
    LC_MONETARY = "es_ES.UTF-8";
    LC_NAME = "es_ES.UTF-8";
    LC_NUMERIC = "es_ES.UTF-8";
    LC_PAPER = "es_ES.UTF-8";
    LC_TELEPHONE = "es_ES.UTF-8";
    LC_TIME = "es_ES.UTF-8";
  };

  console.keyMap = "es";

  nixpkgs.config.allowUnfree = true;

  # Also export the env var so `nix run`, `nix shell`, etc. honour unfree
  # licenses without --impure or per-command setting.
  environment.sessionVariables.NIXPKGS_ALLOW_UNFREE = "1";

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    htop
    tmux
    unzip
    # opencode 2.2.1 from the dedicated `nixpkgs-opencode` flake input, NOT
    # from an upstream flake input. Upstream pins an exact bun via
    # `packageManager`, and its bun.lock and node_modules hash come from that
    # bun, which nixpkgs usually doesn't ship yet, so building it ourselves
    # fails --frozen-lockfile. nixpkgs' package handles this and is prebuilt on
    # cache.nixos.org. It has its own input so an opencode bump doesn't move
    # nixpkgs-unstable (leviathan's kernel/ROCm).
    opencode
  ];
}
