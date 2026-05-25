{ pkgs, ... }:

# llama.cpp with TurboQuant+ — adds new KV cache types (turbo3, turbo4) and
# weight quants (TQ3_1S, TQ4_1S).
#
# Built directly via stdenv.mkDerivation rather than overriding nixpkgs'
# `llama-cpp` recipe — the upstream recipe assumes a webui Node toolchain
# and a `COMMIT` metadata file that the fork's branch doesn't have. Cleaner
# to define a fresh derivation that just runs cmake on the fork's source.
#
# Binaries installed on PATH:
#   llama-cli       interactive chat / completion
#   llama-server    OpenAI-compatible HTTP server (default port 8080)
#   llama-bench     throughput benchmarks
#   llama-quantize  convert / quantize model files
#
# New KV cache types available:
#   --cache-type-k turbo3    3.25 bpw, 4.9× compression vs FP16
#   --cache-type-k turbo4    4.25 bpw, 3.8× compression vs FP16

let
  cudaPkgs = pkgs.cudaPackages;

  llama-cpp-turbo = pkgs.stdenv.mkDerivation {
    pname = "llama-cpp-turboquant";
    version = "feature-turboquant-kv-cache-2026-05-22";

    src = pkgs.fetchFromGitHub {
      owner = "TheTom";
      repo  = "llama-cpp-turboquant";
      rev   = "feature/turboquant-kv-cache";
      hash  = "sha256-lXcjmf2Oqn8Itk77hjmbIBzsVcbzEbNAY/NMV2LVqm0=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      pkg-config
      cudaPkgs.cuda_nvcc
      autoAddDriverRunpath        # patches RPATHs so libcuda is found
    ];

    buildInputs = with pkgs; [
      cudaPkgs.cuda_cudart
      cudaPkgs.cuda_cccl
      cudaPkgs.libcublas
      cudaPkgs.libcurand
    ];

    cmakeFlags = [
      "-DGGML_CUDA=ON"
      "-DCMAKE_BUILD_TYPE=Release"
      "-DLLAMA_BUILD_TESTS=OFF"
      "-DLLAMA_BUILD_EXAMPLES=OFF"
      "-DLLAMA_CURL=OFF"
      "-DCMAKE_CUDA_ARCHITECTURES=86"   # Ampere (RTX 3060 compute capability 8.6)

      # RPATH handling: don't bake the build dir into binaries (nix forbids
      # /build/* references in outputs). Use a $ORIGIN-relative install
      # RPATH so binaries find libllama / libggml / libggml-cuda from
      # $out/lib at runtime.
      "-DCMAKE_SKIP_BUILD_RPATH=OFF"
      "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
      "-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib"
    ];

    # The fork looks for a `COMMIT` file at the source root for version
    # stamping. Create a stub so cmake's metadata step doesn't crash.
    postPatch = ''
      echo "feature-turboquant-kv-cache" > COMMIT
    '';

    # Install just the binaries + ALL shared libraries the build produced
    # (libllama, libggml, libmtmd, etc., plus their .so → .so.N → .so.N.N
    # symlink chains). Skipping CMake's full install (which would include
    # webui assets, headers, cmake-config files we don't need).
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib

      install -Dm755 bin/llama-cli      $out/bin/llama-cli
      install -Dm755 bin/llama-server   $out/bin/llama-server
      install -Dm755 bin/llama-bench    $out/bin/llama-bench
      install -Dm755 bin/llama-quantize $out/bin/llama-quantize

      # Copy every shared library (regular files AND symlinks).
      # -P preserves symlinks as-is; -f overwrites stale ones.
      find . \( -name '*.so' -o -name '*.so.*' \) \( -type f -o -type l \) \
        -exec cp -Pf {} $out/lib/ \;

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "llama.cpp with TurboQuant+ KV cache (turbo3, turbo4)";
      homepage    = "https://github.com/TheTom/llama-cpp-turboquant";
      license     = licenses.mit;
      mainProgram = "llama-cli";
      platforms   = platforms.linux;
    };
  };
in
{
  environment.systemPackages = [ llama-cpp-turbo ];

  # Open the default llama-server port for LAN access (tailscale0 is already trusted).
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
