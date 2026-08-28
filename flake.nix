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
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
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

      # Example nixosConfiguration wiring the module in, for testing
      nixosConfigurations.mcserver-test = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.mcserver
          {
            services.mcserver.enable = true;
          }
        ];
      };

      deploy.nodes.mcserver = {
        # Fill in the target host when deploying
        hostname = "localhost";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.mcserver-test;
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
