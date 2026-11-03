{
  description = "Lighthouse Ops - NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # opencode only. Pinned separately so upgrading opencode never moves
    # nixpkgs-unstable, which also carries leviathan's kernel/ROCm stack.
    # Bump by pointing this at a newer nixos-unstable rev whose opencode is
    # already on cache.nixos.org (check the .narinfo before bumping).
    nixpkgs-opencode.url = "github:NixOS/nixpkgs/0bb2eedc20e4739f29e8045034f2828ad7054f8f";

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

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-opencode, agenix, nix-amd-ai, ... }:
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
          opencode = nixpkgs-opencode.legacyPackages.x86_64-linux.opencode;
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

          # opencode comes from its own pinned input (nixpkgs-opencode), so
          # bumping it never moves nixpkgs-unstable.
          opencode = nixpkgs-opencode.legacyPackages.${system}.opencode;

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
              opencode                              # 2.2.1 from nixpkgs-opencode (cached)
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
