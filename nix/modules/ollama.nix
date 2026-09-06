{ _unstablePkgs, ... }:

# Local LLM runner with GPU acceleration.
# Once running:
#   ollama pull llama3.2
#   ollama run llama3.2
#   curl http://leviathan:11434/api/generate -d '{"model":"llama3.2","prompt":"hi"}'

{
  services.ollama = {
    enable = true;
    acceleration = "rocm";

    # 25.11 would give ollama 0.21.1 built against ROCm 6.4.3. Take the
    # unstable build so ollama's GPU detection matches the ROCm 7.2.3
    # userspace amdgpu.nix installs.
    package = _unstablePkgs.ollama-rocm;   # 0.33.1

    host = "0.0.0.0";           # listen on all interfaces (firewall still gates LAN)
    port = 11434;

    # gfx1201 is in ROCm 7.2.3's default target list and ollama 0.33 detects
    # RDNA 4 natively, so no HSA override should be needed. If `ollama ps`
    # reports 100% CPU, uncomment:
    # rocmOverrideGfx = "12.0.1";
    #
    # Preload models at service start (optional — pulls on first boot).
    # loadModels = [ "llama3.2" "qwen2.5-coder" ];
  };

  networking.firewall.allowedTCPPorts = [ 11434 ];
}
