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
           name = "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL-v2";
           description = "Optimized inference with fixed GPU layers and turbo cache";
           ttl = 3600;
         cmd = ''
            /run/current-system/sw/bin/llama-server \
              -m /data/models/Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL.gguf \
              --spec-type draft-mtp \
              -c 192640 \
              --n-gpu-layers 99 \
              --n-cpu-moe 30 \
              --cache-type-k turbo4 \
              --cache-type-v turbo4 \
              --flash-attn on \
              --batch-size 2048 \
              --ubatch-size 256 \
              --threads 6 \
              --parallel 1 \
              --cont-batching \
              --no-mmap \
              --mlock \
              --temp 0.2 \
              --top-p 0.95 \
              --min-p 0.05 \
              --top-k 20 \
              --host 127.0.0.1 \
              --metrics \
              --port ''${PORT} \
              --chat-template-kwargs '{"preserve_thinking": true}' \
              --slot-save-path /data/cache/
          '';
           aliases = [ "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL-v2" ];
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

  # Only llama-swap is publicly reachable; inner llama-server instances
  # listen on 127.0.0.1 with ports llama-swap assigns dynamically.
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
