# Admin user. Keys listed here get root ssh access too (deploy-rs
# connects as root).
{
  users.users.john = {
    isNormalUser = true;
    description = "John";
    extraGroups = [ "wheel" "users" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSviMIGIHceQvktPkuIWUdQlpeAhNOLq+7i6Bmc/qSF jrobdikeman@gmail.com"
    ];
  };
}