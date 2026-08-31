# Admin user. The key is also given to root (deploy-rs and
# nixos-anywhere connect as root).
let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSviMIGIHceQvktPkuIWUdQlpeAhNOLq+7i6Bmc/qSF jrobdikeman@gmail.com";
in
{
  users.users.john = {
    isNormalUser = true;
    description = "John";
    extraGroups = [ "wheel" "users" ];
    openssh.authorizedKeys.keys = [ sshKey ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];
}