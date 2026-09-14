{
  description = "Lighthouse Ops - NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # AMD AI stack for NixOS (Lemonade server + ROCm/Vulkan llama.cpp,
    # whisper.cpp, stable-diffusion.cpp backends wired declaratively).
    #
    # Deliberately NOT `inputs.nixpkgs.follows` — upstream builds its overlay
    # against its own pinned nixpkgs so the closure hash matches both
    # cache.nixos.org and its Cachix. Pointing it at ours re-hashes every
    # backend and forces a full source rebuild. See the flake's README.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix, nix-amd-ai, ... }:
    let
      mkHost = hostname: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit hostname nixpkgs-unstable nix-amd-ai;
          # Flake reference to nixpkgs-unstable for nixosModules import
          unstableNixpkgs = nixpkgs-unstable;
          # nixpkgs-unstable for packages where nixos-25.11's version is too
          # old (e.g. llama-swap). Construct with allowUnfree so any unfree
          # deps evaluate.
          _unstablePkgs = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        };
        modules = [
          agenix.nixosModules.default
          ./nix/hosts/${hostname}
        ];
      };

      # Systems we expose devShells for.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      nixosConfigurations = {
        lh-satellite = mkHost "lh-satellite";
        leviathan    = mkHost "leviathan";
      };

      devShells = forAllSystems (system:
        let
          # `legacyPackages` honours neither the NIXPKGS_ALLOW_UNFREE env var
          # nor `nixpkgs.config.allowUnfree` from your NixOS modules — the
          # dev shell's pkgs are separate. Construct pkgs explicitly with
          # allowUnfree turned on so unfree deps evaluate.
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # 25.11 has opencode 1.1.14; unstable has 1.18.25 and it is prebuilt
          # on cache.nixos.org.
          upkgs = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };

          # aider-chat's tests check litellm model-catalog metadata that drifts
          # between releases. 3 tests fail against current litellm despite the
          # tool working fine. Skip them.
          aider-chat-no-tests = pkgs.aider-chat.overridePythonAttrs (old: {
            doCheck = false;
            doInstallCheck = false;
          });
        in {
          default = pkgs.mkShell {
            name = "lighthouse-ops";

            packages = with pkgs; [
              # Kubernetes
              kubectl
              kubernetes-helm
              kubectx
              k9s
              kubeseal
              fluxcd
              opentofu
              # Secrets
              age
              agenix.packages.${system}.default
              # GitHub / VCS
              gh
              git
              # JSON / YAML
              jq
              yq-go
              # AI / models
              upkgs.opencode                        # 1.18.25 from nixpkgs-unstable (cached)
              aider-chat-no-tests                    # aider — AI pair programmer (aider.chat); tests disabled (litellm metadata drift)
              python3Packages.huggingface-hub       # provides `hf` (and legacy `huggingface-cli`) on PATH
              # Terminal
              tmux
            ];

            shellHook = ''
              echo "── lighthouse-ops dev shell ─────────────────────────"
              echo "  kubectl   $(kubectl version --client 2>/dev/null | head -1)"
              echo "  helm      $(helm version --short 2>/dev/null)"
              echo "  flux      $(flux --version 2>/dev/null)"
              echo "  k9s       $(k9s version --short 2>/dev/null | grep -i version | head -1)"
              echo "  terraform $(terraform version | head -1)"
              echo "  opencode  $(opencode --version 2>/dev/null)"
              echo "  aider     $(aider --version 2>/dev/null)"
              echo "─────────────────────────────────────────────────────"
            '';
          };
        });
    };
}
