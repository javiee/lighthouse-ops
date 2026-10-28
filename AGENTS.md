# AGENTS.md

High-signal facts for working in this repo. Everything else is in `CLAUDE.md`.

## Nix / flake

- **Flakes ignore untracked files.** `git add` new `.nix` or `.age` files before building, or the build fails with "path not tracked by Git."
- The flake evaluates with `allowUnfree = true` globally (in devShells). **Never set `nixpkgs.config.rocmSupport` (or `cudaSupport`) globally** — it cascades into unrelated packages. Scope GPU support per-package; `llama-cpp` is the only one that needs it.
- `nixpkgs-unstable` is a pinned input. Use `_unstablePkgs` from `specialArgs` in host modules for newer packages — currently llama-swap plus leviathan's whole GPU stack (kernel 6.18, ROCm 7.2.3, llama.cpp). In dev shells, import directly via the helper shown in `flake.nix`.
- `nix flake check` validates the entire flake (no build). Run it before deploying.
- `nix fmt` formats all `.nix` files.

## Deploying from a Mac

`nixos-rebuild` is not installed on darwin. Use:
```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#<hostname> \
  --target-host jcaro@<hostname> --build-host jcaro@<hostname> \
  --sudo --ask-sudo-password
```
The `--build-host` flag builds on the Linux target, not the Mac.

## Secrets (agenix)

- Edit: `cd secrets && EDITOR=vim nix run github:ryantm/agenix -- -e <name>.age`
- Rekey after editing `secrets.nix`: `cd secrets && nix run github:ryantm/agenix -- -r`
- Full workflow: `secrets/HELP.md`
- Plaintext lives in `/run/agenix/<host>` (tmpfs). Survives nothing past reboot.

## Kubernetes secrets

- **NEVER create k8s secrets in the repo.** Do not add Secret YAML templates to Helm charts or check in any secret manifests. Manage secrets externally (sealed-secrets, external-secrets operator, or manual `kubectl create secret`). Reference them in charts via `secretEnv` or `valueFrom.secretKeyRef` only.

## K3s gotchas

- **Kubernetes context is `lh-satellite`.** Always set it (`kubectx lh-satellite` or `kubectl --context lh-satellite`); never use any other context in this project.

- If a custom containerd runtime is ever registered again, **delete the cached containerd config and restart**:
  ```bash
  rm /var/lib/rancher/k3s/agent/etc/containerd/config.toml
  systemctl restart k3s
  ```
- Flannel uses the LAN interface (not `tailscale0`). `--node-ip` is pinned per host to its LAN address.

## Ops

- **Privileged nix options** (`stalled-download-timeout`, `extra-substituters`, `extra-trusted-public-keys`) require the caller to be in `nix.settings.trusted-users`, else they are silently ignored. `[ "root" "@wheel" ]` is set in `nix/modules/common.nix`.
- **Tailscale DNS:** Public DNS only works if a Global nameserver is configured in the Tailscale admin panel.
- **First HIP build on a new host takes a while.** Subsequent builds reuse `/nix/store`. Keep ROCm libs on the cached multi-arch build; pin only our own kernels to `gfx1201`.
- **`nix flake update` bumps leviathan's kernel**, because `boot.kernelPackages` comes from `nixpkgs-unstable`. Use `nixos-rebuild boot` after such a bump, not `switch`.
- ROCm libraries are large; avoid `rocmSupport = true` on anything broader than what needs it.

## Dev shell

`nix develop` (or `direnv` via `.envrc`) provides: `kubectl`, `helm`, `kubectx`, `k9s`, `kubeseal`, `fluxcd`, `opentofu`, `age`, `agenix`, `gh`, `git`, `jq`, `yq-go`, `opencode`, `aider`, `python3Packages.huggingface-hub` (provides `hf`), `tmux`.

- `opencode` comes from `nixpkgs-unstable` (1.18.x, prebuilt on cache.nixos.org); 25.11's is ancient. Don't "fix" it back to `pkgs.opencode`.
- `aider-chat` has tests disabled (`doCheck = false`) — 3 upstream tests fail on litellm metadata drift; the tool itself is fine.

## GitOps workloads / app images

- `gitops/apps/` holds deployed workloads: `hermes-agent` (Helm chart in `charts/hermes-agent`), `pharos-sre-bot`, `ngrok`. CLAUDE.md's "currently empty" note is stale.
- `docker/hermes/Dockerfile` is built/pushed by `.github/workflows/docker-build-push.yml` on pushes to `main` touching `docker/**` → `ghcr.io/javiee/lighthouse-ops/hermes`, tag pinned in the workflow's `HERMES_VERSION` env (bump it manually when changing the image).
- `pharos-sre-bot` has a Flux `ImageUpdateAutomation` that **auto-commits and pushes to `main`** (as `fluxcdbot`) when a new `ghcr.io/javiee/pharos-sre-bot` tag appears. These commits are expected; don't revert or fight them.
- Pre-commit hook: `gitleaks` on staged files (config: `.gitleaksignore`).

## Git

- **NEVER commit changes** unless the user explicitly asks. The user wants to review changes before committing.
- Never push to any branch without explicit permission.
- **NEVER commit secrets, tokens, passwords, API keys, or any credentials** — not even in `.gitignore` or as comments. Use agenix/sealed-secrets/external secret managers only.

## Things to skip

- `.aider.chat.history.md` — stale LLM chat logs, ignore.
- `lab/` — untracked personal scratch (spreadsheets/scripts), not part of the flake.
- `requirements.txt` — leftover from an abandoned Flask experiment, not used.
- `README.md` — empty.
