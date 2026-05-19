{ ... }:

# Local LLM runner with GPU acceleration.
# Once running:
#   ollama pull llama3.2
#   ollama run llama3.2
#   curl http://leviathan:11434/api/generate -d '{"model":"llama3.2","prompt":"hi"}'

{
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "0.0.0.0";           # listen on all interfaces (firewall still gates LAN)
    port = 11434;
    # Preload models at service start (optional — pulls on first boot).
    # loadModels = [ "llama3.2" "qwen2.5-coder" ];
  };

  networking.firewall.allowedTCPPorts = [ 11434 ];
}
