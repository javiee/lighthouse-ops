# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Authorization

Claude is authorized to deploy NixOS configurations and apply GitOps changes in this repo without per-command confirmation, including `nixos-rebuild switch`, `nix flake update`, and `git push` to feature branches. Still confirm before:

- Force-pushing to any branch
- `nixos-rebuild switch` to a host with running workloads, when the change is non-trivial (kernel, network, k3s)
- Destructive operations (k3s wipe, etcd reset, secret deletion, branch deletion)
- Anything touching `main`

## Common commands

```bash
# Validate the entire flake (eval check, no build)
nix flake check

# Format all Nix files
nix fmt

# Build a host configuration locally — does not deploy
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel

# Deploy to a remote host immediately (activate on apply)
nixos-rebuild switch --flake .#<hostname> --target-host <hostname> --use-remote-sudo

# Deploy safely (activates on next reboot — for kernel/early-boot changes)
nixos-rebuild boot --flake .#<hostname> --target-host <hostname> --use-remote-sudo

# Update all flake inputs
nix flake update

# Rollback to the previous system generation (run on the target host)
sudo nixos-rebuild switch --rollback
```

### Deploying from a Mac without `nixos-rebuild` installed

```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#<hostname> \
  --target-host jcaro@<hostname> --build-host jcaro@<hostname> \
  --sudo --ask-sudo-password
```

The `--build-host` flag points at the target so the build happens on the Linux host, not the darwin Mac.

## Hosts

| Host | Role | Notable modules |
|---|---|---|
| `lh-satellite` | K3s server (clusterInit, embedded etcd), Flux GitOps source, kube-prometheus-stack, XFCE workstation | `k3s-bootstrap.nix`, `flux-bootstrap.nix`, `workstation.nix` |
| `leviathan` | K3s agent, GPU-accelerated LLM host (Ollama, llama.cpp), DCGM exporter | `k3s-join.nix`, `nvidia.nix`, `ollama.nix`, `llama-cpp.nix` |

## Architecture

### Repo layout

```
flake.nix                       — defines nixosConfigurations.<host> for each entry below
nix/
  hosts/
    lh-satellite/{default,hardware}.nix
    leviathan/{default,hardware}.nix
  modules/
    common.nix                  — shared base (locale, boot, base packages, including opencode)
    workstation.nix             — XFCE + audio + printing + firefox
    ssh.nix, users.nix, tailscale.nix
    nvidia.nix                  — driver + CDI + container toolkit symlinks
    ollama.nix                  — Ollama service (CUDA, :11434)
    llama-cpp.nix               — llama.cpp built with cudaSupport
    k3s-bootstrap.nix           — server (clusterInit=true, embedded etcd)
    k3s-join.nix                — agents/HA peers (serverAddr to bootstrap node)
    flux-bootstrap.nix          — one-shot systemd unit that runs `flux bootstrap` once
secrets/
  secrets.nix                   — agenix recipients (user age key + each host's SSH host key)
  *.age                         — agenix-encrypted secrets (token files etc.)
  CHEATSHEET.md                 — agenix workflow reference (add new hosts, rekey, recover)
gitops/
  lighthouse-cluster/           — flux bootstrap target (cluster entry point)
  infrastructure/base/          — shared infra HelmReleases (Prometheus, DCGM, etc.)
  apps/                         — workload manifests (currently empty)
```

### Multi-host pattern

`flake.nix` defines a `mkHost` helper that threads the hostname into the host's module via `specialArgs.hostname`. Adding a new host means:

1. `nix/hosts/<name>/default.nix` (imports + hostname + stateVersion)
2. `nix/hosts/<name>/hardware.nix` (generated via `nixos-generate-config` on the box)
3. Append `<name> = mkHost "<name>";` to `nixosConfigurations` in `flake.nix`
4. Add the new host's SSH host key to `secrets/secrets.nix`, then `agenix -r` to rekey

### Secrets via agenix

- `agenix.nixosModules.default` is passed to every host through `flake.nix`.
- Each host can decrypt secrets it's a recipient of, using `/etc/ssh/ssh_host_ed25519_key` at activation. Plaintext lands in `/run/agenix/<name>` (tmpfs).
- All editing happens on the Mac with the user's age key. Adding a new host requires getting its SSH host pubkey (post-install) and adding it to `secrets/secrets.nix`, then `nix run github:ryantm/agenix -- -r` to rekey. If a file can't be decrypted from the Mac (recipient mismatch), see `secrets/CHEATSHEET.md`.

### K3s topology

Embedded-etcd HA-ready cluster. `lh-satellite` initialised with `clusterInit = true`. Additional servers or agents join via `k3s-join.nix`, which reads the same shared token from agenix. Flannel uses the LAN interface (NOT tailscale0) — `--node-ip` is pinned per host to its LAN address so etcd peer URLs stay stable.

### GitOps via Flux

Flux is bootstrapped onto `lh-satellite` by `nix/modules/flux-bootstrap.nix` — a one-shot systemd unit gated by `/var/lib/flux/.bootstrapped`. It points at `github.com/javiee/lighthouse-ops` at path `gitops/lighthouse-cluster`. Anything dropped in `gitops/infrastructure/base/` is picked up by Flux via a Kustomization (see `gitops/lighthouse-cluster/infrastructure.yaml` once present).

### NVIDIA on leviathan

NixOS owns the driver (`hardware.nvidia.open = true` for the Ampere 3060). `hardware.nvidia-container-toolkit.enable = true` generates a CDI spec at `/var/run/cdi/`. K3s' containerd auto-detects the runtime via a symlink at `/usr/local/nvidia/toolkit/nvidia-container-runtime` pointing at `pkgs.nvidia-container-toolkit.tools`. A second symlink at `/usr/bin/nvidia-ctk` covers the CDI hook lookup. `runc` must be in `systemPackages` for the runtime's delegation.

## Deployment workflow gotchas

- **Flakes ignore untracked files.** After creating new `.nix`/`.age` files, `git add` (no commit needed) before `nixos-rebuild`. Otherwise the build fails with "path not tracked by Git."
- **`stalled-download-timeout` is restricted** unless the calling user is in `nix.settings.trusted-users`. `@wheel` is currently trusted (set in `common.nix`).
- **NVIDIA CDN is slow and unreliable.** `nixpkgs.config.cudaSupport = true` cascades through firefox/onnxruntime and triggers multi-gigabyte downloads from NVIDIA. Use per-package `.override { cudaSupport = true; }` instead (the only one is `llama-cpp.nix`).
- **First build on a new host takes hours** if anything is CUDA-built. Subsequent builds reuse `/nix/store`.
- **Tailscale DNS:** with `accept-dns=true` (default), public DNS only works if a Global nameserver is set in the Tailscale admin (https://login.tailscale.com/admin/dns).
- **K3s caches its containerd config.** After changing anything that affects the runtime registration, `rm /var/lib/rancher/k3s/agent/etc/containerd/config.toml && systemctl restart k3s` to force regeneration.

## Reference

- agenix workflow: `secrets/CHEATSHEET.md`
- nixpkgs options search: https://search.nixos.org/options
- systemd unit options: `man 5 systemd.service`, `man 5 systemd.exec`
