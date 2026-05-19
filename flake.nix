{
  description = "Lighthouse Ops - NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix, ... }:
    let
      mkHost = hostname: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit hostname; };
        modules = [
          agenix.nixosModules.default
          ./nix/hosts/${hostname}
        ];
      };
    in {
      nixosConfigurations = {
        lh-satellite = mkHost "lh-satellite";
        leviathan    = mkHost "leviathan";
      };
    };
}
