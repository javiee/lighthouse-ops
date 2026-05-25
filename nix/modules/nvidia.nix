{ config, pkgs, ... }:

# NVIDIA proprietary driver + CUDA toolkit.
# Requires nixpkgs.config.allowUnfree = true (set in common.nix).
#
# For GPUs Turing-or-newer (RTX 20xx+) you can flip `open = true` to use
# the open-kernel driver; older GPUs require the proprietary kernel module.

{

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = true;                 # RTX 3060 is Ampere — open kernel module is NVIDIA-supported here
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # NVIDIA Container Toolkit — lets Docker/Podman pass GPUs into containers.
  hardware.nvidia-container-toolkit.enable = true;

  environment.systemPackages = with pkgs; [
    nvidia-container-toolkit 
    nvtopPackages.full          # GPU monitoring TUI
    nvidia-container-toolkit.tools    # nvidia-container-runtime + hook
    runc
    python3Packages.huggingface-hub   # provides `huggingface-cli` on PATH
  ];

  # NixOS doesn't have /usr/bin or /usr/local/nvidia. Symlink the binaries
  # that the CDI spec and k3s' containerd auto-detection look for there.
  #   - nvidia-container-runtime → in the `.tools` subpackage
  #   - nvidia-ctk → in the main nvidia-container-toolkit package
  systemd.tmpfiles.rules = [
    "L+ /usr/local/nvidia/toolkit/nvidia-container-runtime - - - - ${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime"
    "L+ /usr/bin/nvidia-ctk - - - - ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk"
  ];
}
