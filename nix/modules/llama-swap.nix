{
  pkgs,
  unstable,
  lib,
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
# We use the llama-swap module from nixpkgs-UNSTABLE because nixos-25.11's
# version is missing options we want (e.g. `listenAddress`).
#
# Models live in /data/models so the service's sandbox (ProtectHome=true)
# doesn't block access.

{
  disabledModules = [
    "services/networking/llama-swap.nix"
  ];

  imports = [
    "${unstable.path}/nixos/modules/services/networking/llama-swap.nix"
  ];

  # Ensure /data/models exists and is world-readable for the llama-swap
  # daemon (regardless of which user it runs as).
  systemd.tmpfiles.rules = [
    "d /data           0755 jcaro users -"
    "d /data/models    0755 jcaro users -"
  ];

  services.llama-swap = {
     enable = true;
     package = unstable.packages.${pkgs.system}.llama-swap;
     listenAddress = "0.0.0.0";
     port = 9090;

    settings = {
      healthCheckTimeout = 30; # integer seconds, NOT "30s"
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
              --host 127.0.0.1 \
              --port ''${PORT} \
              --no-mmap
          '';
          aliases = [ "Qwen3.6-35B-A3B-UD-IQ3_XXS" ];
        };

        # ── Q4_K_XL with MTP: higher quality weights, faster decode via MTP ─
        "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL" = {
          name = "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL";
          description = "Higher quality weights, faster decode via MTP";
          ttl = 300;
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
              --port ''${PORT}
          '';
          aliases = [ "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL" ];
        };
      };
    };
  };

  # Only llama-swap is publicly reachable; inner llama-server instances
  # listen on 127.0.0.1 with ports llama-swap assigns dynamically.
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
