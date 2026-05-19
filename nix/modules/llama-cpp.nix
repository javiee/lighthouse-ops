{ pkgs, ... }:

# llama.cpp — efficient CPU/GPU LLM inference (the engine ollama, lm-studio,
# and most local LLM tooling are built on).
#
# Binaries installed on PATH:
#   llama-cli        interactive chat / completion
#   llama-server     OpenAI-compatible HTTP server (default port 8080)
#   llama-bench      throughput benchmarks
#   llama-quantize   convert/quantize model files
#
# CUDA support requires nixpkgs.config.cudaSupport = true (set in nvidia.nix).
# The override below makes it explicit so this still works if you ever turn
# the global flag off.

{
  environment.systemPackages = [
    (pkgs.llama-cpp.override { cudaSupport = true; })
  ];

  # Open the default llama-server port for LAN access (tailscale0 is already trusted).
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
