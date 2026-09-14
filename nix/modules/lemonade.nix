{ lib, nix-amd-ai, _unstablePkgs, ... }:

# Lemonade — AMD's local AI server (OpenAI-compatible), via noamsto/nix-amd-ai.
#
# Why this flake rather than packaging the upstream .deb: Lemonade ships NO
# inference engine (the .deb is 14 MB of web UI). It downloads prebuilt
# llama.cpp/whisper.cpp binaries at runtime, which are FHS-linked and will not
# execute on NixOS. nix-amd-ai instead wires nixpkgs-built engines into
# /etc/lemonade/backends/*, so nothing is fetched at runtime.
#
# ── What this host does and does NOT get ──────────────────────────────────
# enableNPU = false: Lemonade's headline feature is hybrid NPU+GPU execution,
# which needs a Ryzen AI 300/400-series CPU. leviathan has a Ryzen 5 7600X
# (Zen 4 desktop, no XDNA NPU), so the NPU/XRT/FastFlowLM stack is switched
# off entirely. What is left is llama.cpp on ROCm — the same engine llama-swap
# already uses. Lemonade is therefore NOT an LLM speed win here; it is worth
# having for whisper STT, image generation, TTS and its web UI.
#
# ── VRAM: this CONFLICTS with llama-swap ──────────────────────────────────
# The card has 31.86 GiB and llama-swap alone holds ~20 GiB for ttl=3600.
# Upstream's `exclusiveInference` only coordinates lemond <-> ds4-server; it
# knows nothing about our services, so the mutual exclusion is wired by hand
# below. Starting lemond stops llama-swap, and vice versa
# (systemd Conflicts= is bidirectional).
#
# autoStart = false, so llama-swap still owns the GPU at boot. To test:
#   sudo systemctl start lemond      # stops llama-swap
#   curl http://leviathan:13305/api/v1/models
#   sudo systemctl start llama-swap  # hands the GPU back

{
  imports = [ nix-amd-ai.nixosModules.default ];

  # UPSTREAM GAP: with enableImageGen the module wires the CPU backend from
  # `pkgs.stable-diffusion-cpp` (modules/amd-npu.nix:58), but its overlay only
  # exports the -rocm and -vulkan variants — the plain attribute is passed
  # solely into lemonade's own callPackage. nixos-25.11 has no
  # stable-diffusion-cpp, so evaluation fails with "attribute missing". It
  # works upstream only because their consumers track nixos-unstable.
  #
  # Supply it from the same nixpkgs rev nix-amd-ai pins (3ed67ec — identical to
  # our nixpkgs-unstable), so the CPU and ROCm sd-cpp builds stay consistent.
  nixpkgs.overlays = [
    (_final: _prev: {
      inherit (_unstablePkgs) stable-diffusion-cpp;
    })
  ];

  # Upstream's Cachix. MUST live in nix.settings, not flake nixConfig — via
  # nixConfig it is silently ignored for non-trusted users and every backend
  # rebuilds from source. extra-* so cache.nixos.org is not clobbered.
  nix.settings = {
    extra-substituters = [ "https://nix-amd-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };

  hardware.amd-npu = {
    enable = true;

    enableNPU = false;         # no XDNA NPU on a 7600X — keeps the XRT closure out
    enableFastFlowLM = false;  # NPU-only inference runtime; useless without the NPU

    enableLemonade = true;
    enableROCm = true;         # llamacpp-rocm + sd-cpp-rocm backends
    enableVulkan = false;      # ROCm is the good path on a discrete RDNA4 card
    # stable-diffusion.cpp, wiring /etc/lemonade/backends/sdcpp-{rocm,cpu}.
    # Adds a 3.76 GiB closure (measured, and prebuilt on cache.nixos.org — a
    # download, not a compile). The module's own docs say ~1.5 GB; that is low.
    enableImageGen = true;
    enableVllm = false;        # experimental, and see the gpuTarget note below

    # The enum only accepts gfx1150 (Strix Point) / gfx1151 (Strix Halo) — this
    # module was written for Ryzen AI APUs, and our discrete gfx1201 (Navi 48)
    # is not an option. It is inert here: gpuTarget only feeds vllmGpuTarget's
    # default and a gfx1151-specific kernel warning, and enableVllm is false.
    # The ROCm backend itself comes from pkgs.llama-cpp-rocm, whose multi-arch
    # build already covers gfx1201.
    gpuTarget = "gfx1150";

    lemonade = {
      autoStart = false;       # llama-swap keeps the GPU at boot; start this by hand
      host = "0.0.0.0";        # firewall still gates the LAN
      port = 13305;
      user = "jcaro";
      desktopApp.enable = false;  # headless: skips the Tauri Rust + npm build

      # Use the GGUFs already on disk instead of re-downloading from HF.
      # Lemonade scans this tree RECURSIVELY, so both /data/models/*.gguf and
      # /data/models/qwen3.8/*.gguf are picked up (verified: 6 models found).
      #
      # This is the right knob for local files — `customModels` registers by
      # HuggingFace checkpoint (repo:file) and is for *downloading*, not for
      # GGUFs that already exist. Set through `settings` because the module has
      # no dedicated option for it; keys here are re-applied on every lemond
      # start, so a value changed in the web UI is reset on restart.
      settings = {
        extra_models_dir = "/data/models";

        # CRITICAL on this host. With backend="auto" lemonade prefers a
        # llama-server found on PATH ("system") — and llama-cpp.nix puts our
        # TurboQuant fork there for llama-swap. lemond then injects its OWN
        # LEMONADE_GGML_HIP_PATH (upstream llama-cpp 0.3.0 libggml-hip.so) into
        # that fork's process: two incompatible llama.cpp builds in one address
        # space, SIGSEGV (exit 139) the moment warmup touches the backend.
        #
        # Pinning to "rocm" uses llamacpp.rocm_bin (/etc/lemonade/backends/
        # llamacpp-rocm) instead, which matches the injected library.
        # Verified: log flips from "Backend: system" to "Backend: rocm-stable"
        # and the model loads (17.22 GiB VRAM, ~38 tok/s).
        #
        # Merged with lib.recursiveUpdate, so llamacpp.{args,cpu_bin,rocm_bin}
        # from the module are preserved.
        llamacpp.backend = "rocm";

        # Lemonade's default is ctx_size = -1, which does NOT mean "the model's
        # maximum" — it falls back to llama.cpp's built-in 4096. The model
        # trains to 262144, and an opencode request (system prompt + tools +
        # instructions) is ~10.7k tokens, so 4096 fails outright with
        # "request (10666 tokens) exceeds the available context size (4096)".
        #
        # Note this only takes effect on a model RELOAD: a backend already
        # running keeps the ctx-size it was spawned with. `lemonade unload`
        # forces it.
        #
        # Measured at 131072 with Lemonade's f16 KV cache: 25.57 GiB of 31.86.
        # (llama-swap fits the same context in ~24 GiB because it uses q8_0.)
        ctx_size = 131072;
      };
    };
  };

  # Lemonade needs GPU device access as its service user.
  users.users.jcaro.extraGroups = [ "video" "render" ];

  systemd.services.lemond = {
    # Hand-wired mutual exclusion — see the VRAM note above.
    conflicts = [ "llama-swap.service" ];

    # Conflicts= alone is NOT ordered: systemd may start lemond while
    # llama-swap is still shutting down, and llama-server holds ~20 GiB of VRAM
    # until it actually exits — lemond would then fail to allocate. systemd.unit(5)
    # explicitly recommends pairing Conflicts= with After=; that makes the stop
    # job complete before the start job runs.
    after = [ "llama-swap.service" ];

    # The module builds LD_LIBRARY_PATH from the HOST's pkgs.rocmPackages.clr,
    # which on a nixos-25.11 host is ROCm 6.4.3 — while the llama-cpp-rocm it
    # points LEMONADE_GGML_HIP_PATH at comes from the flake's own pinned
    # nixpkgs and is built against ROCm 7.2.3. Loading a 7.2.3 libggml-hip.so
    # against a 6.4.3 runtime is asking for missing symbols. Pin it to the same
    # 7.2.3 clr that amdgpu.nix already puts in hardware.graphics.extraPackages
    # so the whole host agrees on one ROCm.
    environment.LD_LIBRARY_PATH =
      lib.mkForce "${_unstablePkgs.rocmPackages.clr}/lib";

    # Hide the 7600X's integrated GPU, which registers as a second ROCm device
    # (ROCm1, gfx1036). This is a PRECAUTION, not a fix for anything observed:
    # tested both ways, llama-server loads fine with the iGPU visible. It is
    # here because rocBLAS does not support gfx1036, so any llama.cpp that did
    # decide to split layers onto it would be running on an unsupported arch.
    # llama-swap.nix carries the same guard, and lemond spawns its own
    # llama-server processes so it needs its own copy.
    environment.ROCR_VISIBLE_DEVICES = "0";
  };

  networking.firewall.allowedTCPPorts = [ 13305 ];
}
