{
  description = "Lighthouse Ops - NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nix/hardware/hpelitedesk.nix
        ./nix/lh-satellite.nix
        ./nix/tailscale.nix
      ];
    };
  };
}
