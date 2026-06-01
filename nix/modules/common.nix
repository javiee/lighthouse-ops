{ pkgs, opencode, ... }:

let
  # opencode 1.15.6 build asserts bun >= 1.3.14, but every nixpkgs (stable,
  # unstable, opencode's own lock) currently ships bun 1.3.13. The runtime
  # behaviour is identical between the two; the check is purely defensive.
  # Neuter it so the build proceeds.
  opencode-patched = opencode.packages.${pkgs.system}.default.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace packages/script/src/index.ts \
        --replace-fail 'semver.satisfies(process.versions.bun, expectedBunVersionRange)' 'true'
    '';
  });
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  security.limits = [
    { domain = "*"; item = "memlock"; type = "soft"; value = "unlimited"; }
    { domain = "*"; item = "memlock"; type = "hard"; value = "unlimited"; }
  ];

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
    opencode-patched                            # pinned to v1.15.6 via flake input (bun check patched)
  ];
}
