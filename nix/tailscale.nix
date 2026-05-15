{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    tailscale
  ];

  services.tailscale.enable = true;

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ];
  };
}

