{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users.jcaro.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKuC6O7dKxm250GZquodxkltUx3mmEeFT/lyPVpZJTM jcaro@PortatilDesarrolador"
  ];

  networking.firewall.allowedTCPPorts = [ 22 ];
}
