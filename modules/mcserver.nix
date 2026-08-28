# NixOS module for running the All the Mods 10: Aeronautics modded Minecraft server.
#
# Expects the server pack files (mods/, config/, kubejs/, startserver.sh,
# user_jvm_args.txt, ...) to be present in `dataDir`. The NeoForge server
# binaries are installed on first start (same behavior as startserver.sh).
#
# Deployable via deploy-rs by importing `nixosModules.mcserver` into any
# nixosConfiguration.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.mcserver;

  # Java 21 is required by Minecraft 1.21 / NeoForge
  java = cfg.java;

  # Pre-start: download + unpack the server pack from the network if it's
  # not already present at the right version, then install NeoForge if needed,
  # then set up the stdin FIFO for console commands ("stop" on shutdown).
  mcPreStart = pkgs.writeShellScript "mcserver-prestart" ''
    set -eu

    mkdir -p ${cfg.dataDir}
    cd ${cfg.dataDir}

    ${lib.optionalString (cfg.serverPackUrl != null) ''
      INSTALLED_VERSION=$(${pkgs.coreutils}/bin/cat .pack-version 2>/dev/null || true)
      if [ "$INSTALLED_VERSION" != "${cfg.serverPackVersion}" ]; then
        echo "Fetching server pack ${cfg.serverPackVersion} (have: ''${INSTALLED_VERSION:-none})"
        ${pkgs.curl}/bin/curl -fL --retry 5 -o pack.zip "${cfg.serverPackUrl}"
        # Unpack over the existing directory; config/mods etc are overwritten,
        # world/ and other runtime state are not part of the pack.
        ${pkgs.unzip}/bin/unzip -o pack.zip -d .
        rm -f pack.zip
        echo "${cfg.serverPackVersion}" > .pack-version
      fi
    ''}

    INSTALLER="neoforge-${cfg.neoforgeVersion}-installer.jar"
    NEOFORGE_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${cfg.neoforgeVersion}/neoforge-${cfg.neoforgeVersion}-installer.jar"

    if [ ! -d libraries ]; then
      echo "NeoForge not installed, installing now."
      if [ ! -f "$INSTALLER" ]; then
        echo "No NeoForge installer found, downloading now."
        ${pkgs.curl}/bin/curl -fL --retry 5 -o "$INSTALLER" "$NEOFORGE_URL"
      fi
      ${java}/bin/java -jar "$INSTALLER" -installServer
    fi

    if [ ! -e server.properties ]; then
      printf 'allow-flight=true\nmotd=All the Mods 10 Aeronautics\nmax-tick-time=180000' > server.properties
    fi

    # Accept the Minecraft EULA so the server doesn't refuse to start
    ${lib.optionalString cfg.acceptEula ''
      if [ "$(cat eula.txt 2>/dev/null || true)" != "eula=true" ]; then
        printf 'eula=true' > eula.txt
      fi
    ''}

    # stdin FIFO: lets us send console commands (like "stop") to the server
    # for graceful shutdown from ExecStop.
    rm -f /run/mcserver/stdin
    ${pkgs.coreutils}/bin/mkfifo /run/mcserver/stdin
    # Open a permanent writer so java's open of the FIFO doesn't block and
    # later writers don't hit SIGPIPE when no reader is present.
    ${pkgs.coreutils}/bin/tail -f /dev/null > /run/mcserver/stdin &
  '';

  # Main entry: run the server with the FIFO as stdin.
  mcStart = pkgs.writeShellScript "mcserver-start" ''
    cd ${cfg.dataDir}
    exec ${java}/bin/java @user_jvm_args.txt @libraries/net/neoforged/neoforge/${cfg.neoforgeVersion}/unix_args.txt nogui < /run/mcserver/stdin
  '';

  # Graceful shutdown: send "stop" to the server console via the FIFO.
  # systemd waits (up to TimeoutStopSec) for the world save to finish and
  # only falls back to SIGTERM/SIGKILL if the server doesn't exit.
  mcStop = pkgs.writeShellScript "mcserver-stop" ''
    if [ ! -p /run/mcserver/stdin ]; then
      exit 0
    fi
    # timeout guards against hanging forever if the server is wedged
    ${pkgs.coreutils}/bin/timeout 15 ${pkgs.coreutils}/bin/echo stop > /run/mcserver/stdin || true
  '';

  # Health check: block the start job until the server is actually listening
  # on its port (i.e. reached "Done" after loading all mods). If it fails,
  # the unit is marked failed, which fails `switch-to-configuration` and
  # triggers deploy-rs auto/magic rollback.
  mcHealthCheck = pkgs.writeShellScript "mcserver-healthcheck" ''
    DEADLINE=$(( $(date +%s) + ${toString cfg.healthTimeout} ))
    while true; do
      if ${pkgs.iproute2}/bin/ss -tln | grep -q ":${toString cfg.port} "; then
        echo "mcserver is healthy (listening on port ${toString cfg.port})"
        exit 0
      fi
      if [ "$(date +%s)" -ge "$DEADLINE" ]; then
        echo "mcserver FAILED health check: not listening on port ${toString cfg.port} within ${toString cfg.healthTimeout}s"
        ${pkgs.systemd}/bin/journalctl -u mcserver -n 50 --no-pager || true
        exit 1
      fi
      sleep 5
    done
  '';

  mcBackup = pkgs.writeShellScript "mcserver-backup" ''
    set -eu

    BACKUP_DIR=${cfg.backup.backupDir}
    mkdir -p "$BACKUP_DIR"

    STAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)
    OUT="$BACKUP_DIR/world-$STAMP.tar.gz"

    # Save a snapshot of the world directory.
    ${pkgs.gnutar}/bin/tar -czf "$OUT.tmp" -C ${cfg.dataDir} ${lib.concatStringsSep " " cfg.backup.worldDirs}
    mv "$OUT.tmp" "$OUT"

    # Retention: delete backups older than `retentionDays` days.
    ${pkgs.findutils}/bin/find "$BACKUP_DIR" -name 'world-*.tar.gz' -mtime +${toString cfg.backup.retentionDays} -delete
  '';
in
{
  options.services.mcserver = {
    enable = lib.mkEnableOption "the All the Mods 10 Aeronautics Minecraft server";

    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Directory containing the server pack files (mods, config, world, etc).";
      default = "/var/lib/mcserver";
      example = "/var/lib/mcserver";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "john";
      description = "User to run the server as (should own dataDir).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group to run the server as.";
    };

    java = lib.mkOption {
      type = lib.types.package;
      default = pkgs.temurin-bin-21;
      description = "Java runtime to use (Minecraft 1.21 requires Java 21).";
    };

    neoforgeVersion = lib.mkOption {
      type = lib.types.str;
      default = "21.1.248";
      description = "NeoForge version matching the modpack.";
    };

    serverPackUrl = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        URL of a zip of the server pack files (config/, mods/, kubejs/, ...).
        If set, it is downloaded and unpacked into dataDir on start whenever
        serverPackVersion changes (world/ and other runtime state untouched).
        If null, the files must already exist in dataDir.
      '';
    };

    serverPackVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.5.1";
      description = "Version tag of the server pack. Changing it triggers a re-download.";
    };

    acceptEula = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Write eula=true to eula.txt in dataDir so the server is allowed to
        start. By enabling the server you agree to the Minecraft EULA
        (https://aka.ms/MinecraftEULA).
      '';
    };

    healthTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        Seconds to wait for the server to start listening on its port after
        launch (modded servers take minutes to load). If exceeded, the unit
        is marked failed — blocking a NixOS switch and triggering a deploy-rs
        rollback. Make sure this is less than deploy-rs activationTimeout.
      '';
    };

    maxRestarts = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        Maximum number of automatic restarts within restartInterval before
        systemd gives up and leaves the unit in a failed state (instead of
        crash-looping forever). Set high enough that an in-game `stop` at the
        wrong moment can't exhaust it.
      '';
    };

    restartInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1800;
      description = "Time window (seconds) that maxRestarts applies to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 25565;
      description = "Minecraft server port to open in the firewall.";
    };

    autoRestart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether systemd should automatically restart the server on failure/exit.";
    };

    # Periodic restart (e.g. weekly at 5am) to avoid memory creep on modded
    # servers. Set to null to disable.
    periodicRestart = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "Sun, 05:00";
      description = ''
        systemd OnCalendar spec for periodic restarts of the server
        (e.g. "Sun, 05:00"). null disables periodic restarts.
      '';
    };

    backup = {
      enable = lib.mkEnableOption "hourly automatic world backups" // {
        default = true;
      };

      backupDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/mcserver-backups";
        description = "Directory to store world backups in.";
      };

      worldDirs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "world" ];
        description = "Directories inside dataDir to include in backups.";
      };

      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of days of backups to keep.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Open the Minecraft port
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    systemd.services.mcserver = {
      description = "All the Mods 10 Aeronautics Minecraft server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Give up after maxRestarts within restartInterval instead of
      # crash-looping forever; unit ends up in a failed state that's easy to
      # spot (and roll back from).
      unitConfig = {
        StartLimitIntervalSec = cfg.restartInterval;
        StartLimitBurst = cfg.maxRestarts;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        RuntimeDirectory = "mcserver";
        ExecStartPre = "${mcPreStart}";
        ExecStart = "${mcStart}";
        ExecStartPost = "${mcHealthCheck}";
        ExecStop = "${mcStop}";
        Restart = if cfg.autoRestart then "always" else "no";
        RestartSec = 10;
        # Modded servers eat memory; give it plenty before OOM'ing it
        MemoryMax = "20G";
        # "stop" via stdin is the graceful path; these are last-resort.
        KillSignal = "SIGTERM";
        KillMode = "mixed"; # SIGTERM the java main process first
        TimeoutStopSec = 300; # modded world saves can be slow
      };
    };

    # Periodic restart: a oneshot service that stops mcserver; systemd's
    # Restart=always brings it right back up.
    systemd.services.mcserver-periodic-restart = lib.mkIf (cfg.periodicRestart != null) {
      description = "Periodic restart of the Minecraft server";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl try-restart mcserver.service";
      };
    };

    systemd.timers.mcserver-periodic-restart = lib.mkIf (cfg.periodicRestart != null) {
      description = "Timer for periodic Minecraft server restart";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.periodicRestart;
        Persistent = true;
      };
    };

    # Hourly world backups with a week's worth of retention
    systemd.services.mcserver-backup = lib.mkIf cfg.backup.enable {
      description = "Backup the Minecraft world";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mcBackup}";
      };
    };

    systemd.timers.mcserver-backup = lib.mkIf cfg.backup.enable {
      description = "Hourly Minecraft world backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
