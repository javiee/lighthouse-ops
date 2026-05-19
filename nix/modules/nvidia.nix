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
    # cudaPackages.cudatoolkit
    # cudaPackages.cudnn
    nvtopPackages.full          # GPU monitoring TUI
  ];
}
