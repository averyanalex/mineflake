{ lib, pkgs, config, ... }:

with lib; let
  utils = import ./utils.nix { inherit lib; inherit spigot; inherit bungee; };
  default_args = { inherit lib; inherit spigot; inherit bungee; inherit utils; };
  properties = import ./properties.nix default_args;
  permissions = import ./permissions.nix default_args;
  bungeecord = import ./bungeecord.nix default_args;

  cfg = config.minecraft;

  spigot = pkgs.callPackage ../pkgs/spigot { };
  bungee = pkgs.callPackage ../pkgs/bungee { };

  eula-file = utils.mkConfigFile {
    type = "raw";
    data = {
      raw = "eula=true";
    };
  };

  disable-bstats = {
    "plugins/bStats/config.yml" = utils.mkConfig "yaml" {
      enabled = false;
      serverUuid = "00000000-0000-0000-0000-000000000000";
      logFailedRequests = false;
    };
  };
in
{
  options.minecraft = {
    enable = mkEnableOption "If enabled, Nix-defined minecraft servers will be created from minecraft.servers";

    hostAddress = mkOption {
      type = types.str;
      default = "192.168.100.1";
      example = "10.20.0.1";
      description = "Container address in the host system";
    };

    servers = mkOption {
      type = types.attrsOf (types.submodule
        ({ name, ... }: {
          options = {
            localAddress = mkOption {
              type = types.str;
              example = "192.168.100.2";
              description = "Container address in the system in the same with minecraft.hostAddress subnet";
            };

            datadir = mkOption {
              type = types.path;
              default = "/var/lib/minecraft";
              description = "Server data directory";
            };

            secretsFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              example = "config.age.secrets.example-server.path";
              description = "Path to the file that contains the secrets of the server";
            };

            environment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              example = {
                SERVER_NAME = "lobby";
                DISCORD_CHANNEL = "839041965428703253";
              };
              description = "Public secrets (do not use this for passwords or other important information!)";
            };

            binds = mkOption {
              type = types.listOf types.path;
              default = [ ];
              example = [ "/etc/somepath" ];
              description = "List of paths that will be available inside the container (like volumes in docker)";
            };

            ro-binds = mkOption {
              type = types.listOf types.path;
              default = [ ];
              example = [ "/etc/somepath" ];
              description = "List of paths that will be available inside the container in read-only mode (like volumes in docker)";
            };

            extraFlags = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "--drop-capability=CAP_SYS_CHROOT" ];
              description = "List of parameters that will be passed to the systemd-nspawn command";
            };

            opts = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "nogui" ];
              description = "List of parameters that will be passed to the java command after the jar file";
            };

            java_opts = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "-Xmx2048M" "-Xms512M" ];
              description = "List of parameters that will be passed to the java command before the jar file";
            };

            configs = mkOption {
              type = types.attrsOf (types.submodule
                ({ ... }: {
                  options = {
                    type = mkOption {
                      type = types.enum [ "yaml" "json" "raw" ];
                      default = "yaml";
                      example = "raw";
                      description = "Type of config";
                    };

                    data = mkOption {
                      type = types.anything;
                      description = "The contents of the config.";
                      example = { raw = "text"; };
                    };
                  };
                }));
              default = { };
              description = "Attrs with configs";
              example = {
                "path/to/config.yml" = {
                  type = "yaml";
                  data = {
                    some.data = true;
                  };
                };
              };
            };

            permissions = mkOption {
              type = permissions.submodule;
              default = { };
              example = {
                enable = true;
                groups.default = {
                  permissions = [
                    { permission = "some.permission";
                      value = true; }
                  ];
                  prefixes = [
                    { priefix = "VIP ";
                      priority = 10; }
                  ];
                  suffixes = [
                    { suffix = " SMTH";
                      priority = 10; }
                  ];
                };
              };
              description = "LuckPerms settings";
            };

            properties = mkOption {
              type = properties.submodule;
              default = { };
              example = {
                enable = true;
                online-mode = false;
              };
              description = "server.properties settings";
            };

            bungeecord = mkOption {
              type = bungeecord.submodule;
              default = { };
              description = "Bungeecord settings";
            };

            disable-bstats = mkEnableOption "Disable bStats statistics collection";

            jre = mkOption {
              type = types.package;
              default = pkgs.jre;
              description = "Java package";
            };

            maxMemory = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "1024M";
              description = "Max memory in systemd unit and java options";
            };

            minMemory = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "512M";
              description = "Minimum memory in java options";
            };

            CPUWeight = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 100;
              description = "CPUWeight systemd service option";
            };

            CPUQuota = mkOption {
              type = types.nullOr (types.ints.between 0 100);
              default = null;
              example = 20;
              description = "CPUQuota systemd service option (percents)";
            };

            plugins = mkOption {
              type = types.listOf types.package;
              default = [ ];
              example = [ spigot.coreprotect ];
              description = "List of plugins that need to be installed";
            };

            package = mkOption {
              type = types.package;
              default = spigot.paper_1_18_2;
              example = "pkgs.spigot.paper_1_18_2";
              description = "Server package";
            };
          };
        }));
      description = ''
        Attrs of servers to create
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      server-containers = builtins.mapAttrs
        (name: server:
          let
            pre_plugins = server.plugins ++
              (if server.permissions.enable then [ server.permissions.package ] else [ ]);
            # Add plugin depedencies to plugin list
            # TODO: add support for nested depedencies
            plugins = unique (pre_plugins ++
              (concatMap (x: x.meta.deps) pre_plugins));
            configs = utils.recursiveMerge [
              # Server configs
              server.package.meta.configs
              # Plugin configs
              (utils.recursiveMerge (map (plugin: plugin.meta.configs) plugins))
              # bStats
              (optionalAttrs server.disable-bstats disable-bstats)
              # Generators
              (permissions.generator server.permissions)
              (properties.generator server.properties)
              (bungeecord.generator server.bungeecord)
              # User configs (highest priority)
              server.configs
            ];
          in
          {
            name = "mf-${name}";
            value = {
              autoStart = true;
              privateNetwork = true;
              hostAddress = cfg.hostAddress;
              localAddress = server.localAddress;
              extraFlags = (map (path: "--bind-ro=${path}") (server.ro-binds ++ (if server.secretsFile != null then [ server.secretsFile ] else [ ]))) ++
                (map (path: "--bind=${path}") server.binds) ++ server.extraFlags;
              config = { config, pkgs, ... }: {
                systemd.services.minecraft = {
                  restartIfChanged = true;
                  wantedBy = [ "multi-user.target" ];
                  wants = [ "network-online.target" ];
                  after = [ "network-online.target" ];
                  description = "${name} mineflake server configuration.";
                  environment = server.environment;
                  serviceConfig = utils.recursiveMerge [
                    {
                      Type = "simple";
                      User = "minecraft";
                      Group = "minecraft";
                      SyslogIdentifier = "minecraft";
                      WorkingDirectory = "${server.datadir}";
                      ExecStart = ''${server.jre}/bin/java ${builtins.toString (builtins.map (x: "\""+x+"\"") (server.java_opts ++
                        (optional (server.minMemory != null) "-Xms${server.minMemory}") ++
                        (optional (server.maxMemory != null) "-Xmx${server.maxMemory}")))} -jar ${server.package}/result ${builtins.toString (builtins.map (x: "\""+x+"\"") server.opts)}'';
                      ReadWritePaths = [ server.datadir ];
                      CapabilityBoundingSet = "";
                      NoNewPrivileges = true;
                      ProtectSystem = "strict";
                      ProtectHome = true;
                      PrivateTmp = true;
                      PrivateDevices = true;
                      PrivateUsers = true;
                      ProtectHostname = true;
                      ProtectClock = true;
                      ProtectKernelTunables = true;
                      ProtectKernelModules = true;
                      ProtectKernelLogs = true;
                      ProtectControlGroups = true;
                      RestrictAddressFamilies = [ "AF_UNIX AF_INET AF_INET6" ];
                      LockPersonality = true;
                      RestrictRealtime = true;
                      RestrictSUIDSGID = true;
                      PrivateMounts = true;
                    }
                    (optionalAttrs (server.secretsFile != null) { EnvironmentFile = server.secretsFile; })
                    (optionalAttrs (server.CPUWeight != null) { CPUWeight = toString server.CPUWeight; })
                    (optionalAttrs (server.CPUQuota != null) { CPUQuota = (toString server.CPUQuota) + "%"; })
                    (optionalAttrs (server.maxMemory != null) { MemoryLimit = server.maxMemory; })
                  ];
                  preStart = ''
                    # Generated by mineflake. Do not edit this file.
                    echo "Create directories for core ${utils.getName server.package}..."
                    ${optionalString (length server.package.meta.folders >= 1)
                      ''mkdir -p ${toString (map (folder: "\"" + server.datadir + "/" + folder + "\"") server.package.meta.folders)}''}
                    ${concatStringsSep "\n" (map (
                      plugin:
                        optionalString (length plugin.meta.folders >= 1)
                        ''
                          echo "Create directories for ${utils.getName plugin}..."
                          mkdir -p ${toString (map (folder: "\"" + server.datadir + "/" + folder + "\"") plugin.meta.folders)}
                        ''
                      ) plugins)}
                    echo "Change directory to server data..."
                    cd "${server.datadir}/"
                    ${optionalString (server.package.meta.server == "spigot") ''
                      echo "eula.txt generation..."
                      rm -f "${server.datadir}/eula.txt"
                      ln -sf "${eula-file}" "${server.datadir}/eula.txt"''}
                    echo "Remove old plugin symlinks..."
                    rm -f ${server.datadir}/plugins/*.jar
                    ${concatStringsSep "\n" (map (
                      plugin: if plugin.meta.type == "result" then
                        (utils.linkResult plugin (server.datadir + "/plugins") ".jar")
                        else if plugin.meta.type == "complex" then
                        (utils.linkComplex plugin (server.datadir)) + "\n" +
                        ''ln -sf "${plugin}/result" "${server.datadir}/plugins/${utils.getName plugin}.jar"'' + "\n"
                        else "echo 'Unsupported ${utils.getName plugin} plugin type ${plugin.meta.type}!'") plugins)}
                    ${optionalString (server.package.meta.type == "complex") (utils.linkComplex server.package (server.datadir))}
                    ${utils.mkConfigs server configs}
                    echo "Link server core for easier debug and local launch..."
                    rm -f ${server.datadir}/server-*.jar
                    ln -sf "${server.package}/result" "${server.datadir}/server-${utils.getName server.package}.jar"
                  '';
                };

                users = {
                  users.minecraft = {
                    createHome = true;
                    isSystemUser = true;
                    home = server.datadir;
                    group = "minecraft";
                    description = "System account that runs ${name} mineflake server configuration.";
                  };
                  groups.minecraft = { };
                };

                networking.firewall.enable = false;

                system.stateVersion = "22.05";
              };
            };
          })
        cfg.servers; in
    { containers = builtins.listToAttrs (map (key: getAttr key server-containers) (attrNames server-containers)); } //
    {
      # TODO: check if plugins have same server type value with server.package
      assertions = [];
    }
  );
}