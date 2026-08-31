# Minecraft server flake.
#
# Exposes `nixosModules.mcserver`, a NixOS module that sets up and runs the
# All the Mods 10: Aeronautics modded server (see ./modules/mcserver.nix).
#
# The server pack files live in ./serverfiles (untracked, ~900MB).
{
  description = "Modded Minecraft server NixOS module (All the Mods 10: Aeronautics)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      deploy-rs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosModules.mcserver = import ./modules/mcserver.nix;
      nixosModules.default = self.nixosModules.mcserver;

      # The actual box (Cameron's server). Installs with nixos-anywhere:
      #   nixos-anywhere \
      #     --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
      #     --flake .#mcserver --target-host root@<host>
      # (regenerates ./hardware-configuration.nix for the real machine)
      nixosConfigurations.mcserver = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.default
          ./hosts/mcserver.nix
        ];
      };

      deploy.nodes.mcserver = {
        # Cameron's public IP or hostname (see DDNS note in CAMERON.md)
        hostname = "FILL_ME_IN";
        autoRollback = true;
        magicRollback = true;
        profiles.system = {
          user = "root";
          # activation blocks until the mcserver health check passes, so this
          # must exceed services.mcserver.healthTimeout (600s default)
          activationTimeout = 900;
          waitsFor = "systemd-switch";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.mcserver;
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
