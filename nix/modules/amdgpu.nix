{ pkgs, lib, _unstablePkgs, ... }:

# AMD Radeon AI PRO R9700 — Navi 48 (RDNA 4), LLVM target gfx1201, 32 GB GDDR6.
#
# Unlike NVIDIA there is no out-of-tree kernel module: the in-tree `amdgpu`
# driver binds the card and pulls GC 12.0.x microcode from linux-firmware.
# Nothing here is unfree, and nothing needs a vendor CDN.
#
# ── Why this module reaches into nixpkgs-unstable ──────────────────────────
# The host stays a nixos-25.11 system; only the GPU stack is pulled forward,
# the same way llama-swap.nix already does. 25.11 would technically work, but:
#
#   kernel  6.12.93 → 6.18.48   25.11's amdgpu only binds Navi 48 through the
#                               PCI IP-discovery catch-all; 6.18 has it as a
#                               first-class device.
#   ROCm    6.4.3   → 7.2.3     Both list gfx1201, but 7.x is where RDNA 4
#                               gets real kernel/library tuning.
#
# Keep the kernel and linux-firmware from the SAME nixpkgs so a 6.18 driver
# never asks 25.11's older firmware (20260519) for a blob it doesn't ship.

let
  rocmPkgs = _unstablePkgs.rocmPackages;   # 7.2.3
in
{
  boot.kernelPackages = _unstablePkgs.linuxPackages_6_18;
  hardware.firmware = lib.mkBefore [ _unstablePkgs.linux-firmware ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    # OpenCL via the ROCm runtime. Set explicitly rather than through
    # `hardware.amdgpu.opencl.enable`, because that option wires in 25.11's
    # rocmPackages.clr (6.4.3) and would leave the box running ROCm 6 for
    # OpenCL while HIP runs on 7.2.3.
    extraPackages = [
      rocmPkgs.clr
      rocmPkgs.clr.icd
    ];
  };

  # The NixOS default is [ "modesetting" "fbdev" ] — "amdgpu" is only in the
  # option's *example*, not its default. Name it explicitly so Xorg loads
  # xf86-video-amdgpu, with modesetting kept as the fallback.
  services.xserver.videoDrivers = [ "amdgpu" "modesetting" ];

  # Bind amdgpu in the initrd so KMS/console comes up on the dGPU.
  hardware.amdgpu.initrd.enable = true;

  # Clean up after nvidia.nix. Its `L+` tmpfiles rules created these symlinks;
  # systemd-tmpfiles only acts on rules that still exist, so deleting the rules
  # leaves the symlinks behind as dangling pointers into a GC'd store path.
  # `r` removes them once, then becomes a no-op.
  systemd.tmpfiles.rules = [
    "r /usr/local/nvidia/toolkit/nvidia-container-runtime - - - - -"
    "r /usr/bin/nvidia-ctk - - - - -"
  ];

  environment.systemPackages = [
    rocmPkgs.rocminfo                        # `rocminfo` — should report gfx1201
    rocmPkgs.rocm-smi                        # `rocm-smi` — power / clocks / VRAM
    _unstablePkgs.amdgpu_top                 # GPU monitoring TUI (the nvtop analogue)
    _unstablePkgs.nvtopPackages.amd          # `nvtop`, AMD-only build
    pkgs.python3Packages.huggingface-hub     # provides `huggingface-cli` on PATH
  ];
}
