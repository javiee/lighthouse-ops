{
  description = "Lighthouse Ops - NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opencode = {
      url = "github:sst/opencode/v1.15.6";
      # opencode 1.15.6 needs bun >= 1.3.14. Our nixos-25.11 has 1.3.3,
      # opencode's own lock has 1.3.13. nixpkgs-unstable has new-enough bun.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix, opencode, ... }:
    let
      mkHost = hostname: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit hostname opencode nixpkgs-unstable;
          # Flake reference to nixpkgs-unstable for nixosModules import
          unstableNixpkgs = nixpkgs-unstable;
          # nixpkgs-unstable for packages where nixos-25.11's version is too
          # old (e.g. llama-cpp). Construct with allowUnfree so its CUDA
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
          # allowUnfree turned on so CUDA / NVIDIA deps evaluate.
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          opencode-patched = opencode.packages.${system}.default.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace packages/script/src/index.ts \
                --replace-fail 'semver.satisfies(process.versions.bun, expectedBunVersionRange)' 'true'
            '';
          });

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
              opencode-patched                      # pinned to v1.15.6 (bun check patched)
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
