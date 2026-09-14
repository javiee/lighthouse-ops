{
  pkgs,
  lib,
  nixpkgs-unstable,    # flake input — usable as a path string
  _unstablePkgs,       # pre-imported pkgs from unstable with allowUnfree on
  ...
}:

# llama-swap — proxy + on-demand model swapper for llama-server.
# Single endpoint (:9090) that starts/stops llama-server instances based on
# the requested model ID. Lets us run multiple llama-server-managed models
# with only one loaded at a time (the way ollama does, but with full
# llama.cpp flag control — turboquant, --override-tensor, etc.).
#
# After deploy:
#   curl http://leviathan:9090/v1/models
#   curl http://leviathan:9090/v1/chat/completions -d '{"model":"<id>",...}'
#
# We pull the llama-swap module + binary from nixpkgs-UNSTABLE because
# nixos-25.11's version is missing options we want (e.g. `listenAddress`).
#
# Models live in /data/models so the service's sandbox (ProtectHome=true)
# doesn't block access.

{
  disabledModules = [
    "services/networking/llama-swap.nix"
  ];

  imports = [
    # Use the flake input directly as a path. Accessing `.path` on an
    # evaluated pkgs set caused infinite recursion (lazy chain ends up
    # referencing host config). The raw flake source has no such tie-in.
    "${nixpkgs-unstable}/nixos/modules/services/networking/llama-swap.nix"
  ];

  # Ensure /data/models exists and is world-readable for the llama-swap
  # daemon (regardless of which user it runs as).
  systemd.tmpfiles.rules = [
    "d /data           0755 jcaro users -"
    "d /data/models    0755 jcaro users -"
    "d /data/cache     0755 jcaro users -"
  ];

  services.llama-swap = {
    enable = true;
    package = _unstablePkgs.llama-swap;   # use unstable's llama-swap binary
    listenAddress = "0.0.0.0";
    port = 9090;

    settings = {
      healthCheckTimeout = 30;            # integer seconds, NOT "30s"
      metricsMaxInMemory = 1000;
      performance = {
        enable = true;
        every = "15s";
      };

      models = {
        # ─────────────────────────────────────────────────────────────────────
        # ACTIVE: Qwen3.8-27B (dense, 27.32B params)
        #
        # Sizing — MEASURED on the R9700 (31.86 GiB usable), not calculated.
        # llama-server loaded at -ngl 99 with q8_0 KV + MTP:
        #
        #   ctx  65536  ->  21.73 GiB
        #   ctx  98304  ->  22.92 GiB
        #   ctx 131072  ->  23.99 GiB   <- current, ~7.9 GiB headroom
        #
        # Do NOT size this from the GGUF header. Computing it as
        # 65 blocks x head_count_kv 4 x (key_length 256 + value_length 256)
        # = 133,120 elems/token at 8.5 bpw predicts ~17.3 GiB of KV at 131072
        # and "will not fit" — about 4x too pessimistic. The measured cost is
        # roughly 1.1 GiB per additional 32768 tokens, because llama.cpp does
        # not reserve the whole cache up front.
        #
        # Caveat: those figures are taken right after load. A conversation that
        # genuinely fills 131072 tokens will grow beyond them, so the headroom
        # is smaller than it looks. If long sessions OOM, step down to 98304.
        #
        # No --n-cpu-moe: dense model, and it fits entirely in VRAM anyway.
        #
        # --spec-type draft-mtp: this GGUF ships its own Multi-Token Prediction
        # head — blk.64.nextn.*, which is why block_count is 65 for a 64-layer
        # model. No external draft model is needed. The MTP head drafts ahead
        # and the full model verifies a whole batch in ONE forward pass, so
        # accepted tokens cost no extra weight read.
        #
        # This is why it beats the naive memory-bandwidth ceiling: 640 GB/s over
        # 17.54 GB of weights caps plain decoding at ~36.5 tok/s, but measured
        # through lemonade with MTP on we saw 38.2 tok/s at draft_n=6 /
        # accepted=4 (67%), versus 27 tok/s without it. Same weights, same card.
        #
        # reasoning_effort: the GGUF chat template defaults to 'xhigh' and
        # accepts only xhigh | medium | low (it raise_exception's on anything
        # else; 'high' is silently remapped to xhigh). 'medium' cuts the length
        # of the thinking block, so answers arrive sooner even though t/s is
        # unchanged — generation here is memory-bandwidth bound at ~27 t/s.
        # ─────────────────────────────────────────────────────────────────────
        "Qwen3.8-27B-UD-Q4_K_XL" = {
          name = "Qwen3.8-27B-UD-Q4_K_XL";
          description = "Qwen3.8 27B dense, Q4_K_XL, 128k ctx, turbo4 KV, all on GPU";
          ttl = 3600;
          cmd = ''
            /run/current-system/sw/bin/llama-server \
              -m /data/models/qwen3.8/Qwen3.8-27B-UD-Q4_K_XL.gguf \
              --alias Qwen3.8-27B-UD-Q4_K_XL \
              --device ROCm0 \
              -ngl 99 \
              -c 131072 \
              --spec-type draft-mtp \
              --cache-type-k q8_0 --cache-type-v q8_0 \
              --flash-attn on \
              --batch-size 2048 \
              --ubatch-size 512 \
              --threads 6 \
              -np 1 \
              --cont-batching \
              --no-mmap \
              --jinja \
              --chat-template-kwargs '{"reasoning_effort":"medium"}' \
              --metrics \
              --host 127.0.0.1 \
              --port ''${PORT} \
              --slot-save-path /data/cache/
          '';
          aliases = [ "Qwen3.8-27B" ];
        };

        # ─────────────────────────────────────────────────────────────────────
        # DISABLED 2026-09-06 with the RTX 3060 → Radeon AI PRO R9700 swap.
        # These were all tuned for a 12 GB card (note the --n-cpu-moe values,
        # which pushed 30-40 MoE layers onto the CPU). On 32 GB they would run,
        # but the offload settings are wrong and they are not what is wanted
        # right now. Kept verbatim for reference / easy re-enable.
        # ─────────────────────────────────────────────────────────────────────
        /*
        # ── IQ3_XXS: smaller, faster, longer context, no MTP ────────────────
        "Qwen3.6-35B-A3B-UD-IQ3_XXS" = {
          name = "Qwen3.6-35B-A3B-UD-IQ3_XXS";
          description = "Smaller, faster, longer context, no MTP";
          ttl = 300;
          cmd = ''
            /run/current-system/sw/bin/llama-server \
              -m /data/models/Qwen3.6-35B-A3B-UD-IQ3_XXS.gguf \
              --alias Qwen3.6-35B-A3B-UD-IQ3_XXS \
              --n-gpu-layers 99 \
              --n-cpu-moe 30 \
              -c 65536 \
              --cache-type-k turbo4 --cache-type-v turbo4 \
              --flash-attn on \
              --cont-batching \
              --jinja \
              --metrics \
              --host 127.0.0.1 \
              --port ''${PORT} \
              --no-mmap \
              --slot-save-path /data/cache/
          '';
          aliases = [ "Qwen3.6-35B-A3B-UD-IQ3_XXS" ];
        };

        # ── Q4_K_XL with MTP: higher quality weights, faster decode via MTP ─
         "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL" = {
           name = "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL";
           description = "Higher quality weights, faster decode via MTP";
           ttl = 3600;
           cmd = ''
             /run/current-system/sw/bin/llama-server \
               -m /data/models/Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL.gguf \
               --spec-type draft-mtp \
               -c 65536 \
               --n-cpu-moe 35 \
               -ngl auto \
               -fa on \
               --spec-draft-n-max 2 \
               --cache-type-k-draft q8_0 \
               --cache-type-v-draft q8_0 \
               --cache-type-k q8_0 \
               --cache-type-v q8_0 \
               -np 1 \
               --jinja \
               --host 127.0.0.1 \
               --metrics \
               --port ''${PORT} \
               --chat-template-kwargs '{"preserve_thinking": true}' \
               --slot-save-path /data/cache/
           '';
           aliases = [ "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL" ];
         };

         # ── Q4_K_XL with MTP: optimized inference, fixed GPU layers ──────────
         "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL-v2" = {
           name = "Qwen3.6-35B-A3B-MTP-V2";
           description = "Optimized inference with fixed GPU layers and turbo cache";
           ttl = 3600;
           cmd = ''
             /run/current-system/sw/bin/llama-server \
               -m /data/models/Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL.gguf \
               --spec-type draft-mtp \
               -c 192640\
               --n-cpu-moe 40 \
               -ngl auto \
               -fa on \
               --spec-draft-n-max 2 \
               --cache-type-k turbo4 \
               --cache-type-v turbo4 \
               --flash-attn on \
               --batch-size 2048 \
               --ubatch-size 256 \
               --threads 6 \
               -np 1 \
               --cont-batching \
               --no-mmap \
               --mlock \
               --temp 0.2 \
               --top-p 0.95 \
               --min-p 0.05 \
               --top-k 20 \
               --jinja \
               --host 127.0.0.1 \
               --metrics \
               --port ''${PORT} \
               --chat-template-kwargs '{"preserve_thinking": true}' \
               --slot-save-path /data/cache/
           '';
           aliases = [ "Qwen3.6-35B-A3B-MTP-V2" ];
         };

        # ── APEX I-Balanced: large context (192k), high GPU layer count ──────
        "Qwen3.6-35B-A3B-APEX-I-Balanced" = {
          name = "Qwen3.6-35B-A3B-APEX-I-Balanced";
          description = "APEX I-Balanced quantization, 192k context";
          ttl = 3600;
          cmd = ''
            /run/current-system/sw/bin/llama-server \
              -m /data/models/Qwen3.6-35B-A3B-APEX-I-Balanced.gguf \
              --alias Qwen3.6-35B-A3B-APEX-I-Balanced \
              -c 192640 \
              -ngl auto \
              --n-cpu-moe 30 \
              --cache-type-k turbo4 --cache-type-v turbo4 \
              -fa on \
              --batch-size 2048 \
              -np 1 \
              --ubatch-size 512 \
              --threads 6 \
              --cont-batching \
              --no-mmap \
              --mlock \
              --timeout 300 \
              --jinja \
              --metrics \
              --host 127.0.0.1 \
              --port ''${PORT} \
              --chat-template-kwargs '{"preserve_thinking": true}' \
              --slot-save-path /data/cache/
          '';
          aliases = [ "Qwen3.6-35B-A3B-APEX-I-Balanced" ];
        };
        */
      };
    };
  };

  # Override the upstream module's aggressive sandboxing — llama-swap reads
  # /proc/meminfo (blocked by ProcSubset=pid) and we want it to access models
  # in /data/models (blocked by ProtectSystem=strict).
  #
  # We apply mkForce per-attribute so the upstream serviceConfig (ExecStart,
  # User, etc.) is preserved. Wrapping the whole attrset in mkForce REPLACES
  # the entire serviceConfig, killing ExecStart — which is what just broke
  # the unit.
  systemd.services.llama-swap.serviceConfig = {
    ProtectHome           = lib.mkForce false;
    ProtectSystem         = lib.mkForce false;
    ProtectClock          = lib.mkForce false;
    ProtectControlGroups  = lib.mkForce false;
    ProtectKernelLogs     = lib.mkForce false;
    ProtectKernelModules  = lib.mkForce false;
    ProtectKernelTunables = lib.mkForce false;
    ProtectHostname       = lib.mkForce false;
    ProtectProc           = lib.mkForce "default";   # was "no-invoke" — invalid value
    ProcSubset            = lib.mkForce "all";       # exposes /proc/meminfo etc.
    PrivateDevices        = lib.mkForce false;
    PrivateTmp            = lib.mkForce false;
    PrivateMounts         = lib.mkForce false;
    PrivateUsers          = lib.mkForce false;
    MemoryDenyWriteExecute = lib.mkForce false;
    LockPersonality       = lib.mkForce false;
    RestrictNamespaces    = lib.mkForce false;
    RestrictRealtime      = lib.mkForce false;
    RestrictSUIDSGID      = lib.mkForce false;
    NoNewPrivileges       = lib.mkForce false;
    LimitMEMLOCK          = lib.mkForce "infinity";
  };

  # The Ryzen 7600X's integrated GPU also registers as a ROCm device
  # (ROCm1, gfx1036). Unlike ollama — which drops it automatically with
  # "no rocblas support for gfx target" — llama.cpp will happily split layers
  # onto it, backed by system RAM, which is both slow and liable to fail on an
  # arch rocBLAS does not support. Hide it so every llama-server that
  # llama-swap spawns sees only the R9700 as ROCm0.
  systemd.services.llama-swap.environment.ROCR_VISIBLE_DEVICES = "0";

  # Only llama-swap is publicly reachable; inner llama-server instances
  # listen on 127.0.0.1 with ports llama-swap assigns dynamically.
  networking.firewall.allowedTCPPorts = [ 9090 ];

  # Proactive OOM protection. The mlock'd model weights + KV cache can't be
  # reclaimed under pressure, so the in-kernel OOM killer is too slow and the
  # box thrashes/freezes. earlyoom kills the biggest hog *before* the freeze,
  # keeping the control plane (sshd/k3s/tailscale) alive.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;     # act when <5% RAM free
    freeSwapThreshold = 100;  # no swap on this host, so this is effectively RAM-only
    enableNotifications = false;
    extraArgs = [
      # Prefer to sacrifice the model server, never the control plane.
      # Process names, not service names. llama-swap spawns `llama-server`;
      # lemonade execs its backend symlink so its process is `llamacpp-rocm`
      # (and `sdcpp-rocm` for image generation). ollama was removed 2026-09-07.
      "--prefer" "^(llama-server|llamacpp-rocm|sdcpp-rocm|lemond)$"
      "--avoid" "^(sshd|k3s|systemd|tailscaled|containerd)$"
    ];
  };
}
