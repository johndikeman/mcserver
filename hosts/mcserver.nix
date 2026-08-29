# Host configuration for the Minecraft server box (Cameron's machine).
# This is what nixos-anywhere installs and what deploy-rs deploys.
#
# Kept simple: everything specific to running the game server lives in
# modules/mcserver.nix; this file is just "make a bootable server with
# ssh access".

{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../modules/mcserver.nix
    ../users/john.nix

    # Disk layout, used by nixos-anywhere to wipe + partition.
    # WARNING: nixos-anywhere will ERASE the disk this points at.
    ../disko.nix
  ];
  disko.devices.disk.main.device = "/dev/nvme0n1";

  # ----- Boot -----
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ----- Kernel / hardware -----
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  # RAM disk for the modded server heap; let nix detect zram/etc later
  zramSwap.enable = true;

  # ----- Networking -----
  networking.hostName = "mcserver";
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      # DHCP on every wired interface; fine for a home server
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      networkConfig.DHCP = "yes";
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    # 25565 opened by services.mcserver
  };

  # ----- The game server -----
  services.mcserver = {
    enable = true;
    # Server pack files are rsynced into /var/lib/mcserver after install;
    # with serverPackUrl = null the pre-start script skips downloading.
    serverPackUrl = "https://github.com/johndikeman/mcserver/releases/download/v1/server.zip";
    serverPackVersion = "v1";
  };
}

