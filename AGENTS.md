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

`nix develop` (or `direnv` via `.envrc`) provides: `kubectl`, `helm`, `fluxcd`, `k9s`, `kubeseal`, `opentofu`, `age`, `agenix`, `gh`, `git`, `jq`, `yq-go`, `opencode`, `aider`, `python3Packages.huggingface-hub` (provides `hf`), `tmux`.

## Git

- **NEVER commit changes** unless the user explicitly asks. The user wants to review changes before committing.
- Never push to any branch without explicit permission.
- **NEVER commit secrets, tokens, passwords, API keys, or any credentials** — not even in `.gitignore` or as comments. Use agenix/sealed-secrets/external secret managers only.

## Things to skip

- `.aider.chat.history.md` — stale LLM chat logs, ignore.
- `requirements.txt` — leftover from an abandoned Flask experiment, not used.
- `README.md` — empty.
