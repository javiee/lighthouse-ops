{ pkgs, _unstablePkgs, ... }:

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
    # opencode from nixpkgs-unstable (1.18.25), NOT from an upstream flake
    # input. Upstream pins `packageManager: bun@1.3.14`, and both its bun.lock
    # and its node_modules fixed-output hash come from that exact bun — which
    # no nixpkgs channel ships (25.11: 1.3.3, unstable: 1.3.13). Building it
    # ourselves therefore fails --frozen-lockfile. nixpkgs' own package handles
    # this and is prebuilt on cache.nixos.org, so we get a working binary with
    # no build at all. 25.11's opencode is far too old (1.1.14), hence unstable.
    _unstablePkgs.opencode
  ];
}
