{ pkgs, ... }:

{
  users.users.jcaro = {
    isNormalUser = true;
    description = "Javi";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
  };
  programs.zsh = {
    enable = true;
    interactiveShellInit = "bindkey -e";
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "docker" "kubectl" ];
      theme = "robbyrussell";
    };
  };
}
