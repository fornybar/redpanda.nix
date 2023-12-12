{ config, lib, pkgs, ... }:
with lib;

let
  inherit (builtins) isList;

  cfg = config.services.redpanda;

  rpkCmd = "rpk --config ${cfg.configDir}/redpanda.yaml";

  yaml = pkgs.formats.yaml { };

  brokerCfg = cfg.settings;

  brokerYaml = yaml.generate "redpanda.yaml" brokerCfg;

  clusterYaml = yaml.generate "redpanda-cluster.yaml" cfg.cluster.settings;

  # Find all address/port sets in broker configuration, for opening dynamically
  hasPort = x: (x ? address) && (x ? port);
  portCfg = lib.attrsets.collect hasPort brokerCfg; # Specified in sets
  listedPortCfg = lib.lists.flatten (# Specified in list of sets
    lib.attrsets.collect
      (x: isList x && (lib.lists.all hasPort x))
      brokerCfg
  ); # We do not search down in these attrsets

  # XXX: this includes internal stuff, no?
  portsToOpen = map (x: x.port) (portCfg ++ listedPortCfg);

  mkAddressOption = address: port: {
    port = mkOption { type = types.port; default = port; };
    address = mkOption { type = types.str; default = address; };
  };

  clusterEntryDefinition = types.submodule {
    options = {
      seed = mkOption {
        type = types.bool;
        default = true;
        description = "Is this broker a seed server in the cluster";
      };
      advertised_rpc_api = mkAddressOption "0.0.0.0" 33145;
      advertised_kafka_api = mkOption {
        type = types.listOf (types.submodule {
          options = mkAddressOption "0.0.0.0" 9092;
        });
      };
    };
  };

in
{
  options.services.redpanda = with types; {
    enable = mkEnableOption "redpanda";

    packages = {
      client = mkOption {
        type = package;
        default = pkgs.redpanda;
        defaultText = literalExpression "pkgs.redpanda";
        description = "Which Redpanda client package to use";
      };
      server = mkOption {
        type = package;
        # currently broken. must override
        default = pkgs.redpanda-server;
        defaultText = literalExpression "pkgs.redpanda-server";
        description = "Which Redpanda server package to use";
      };
    };

    configDir = mkOption {
      type = path;
      description = "Directory of redpanda config";
      # XXX: does this work if it's not `/var/lib/redpanda`? redpanda puts a pid flie at `/var/lib/redpanda/data/pid.lock`, and i'm not sure we can change that.
      default = "/var/lib/redpanda";
    };

    openPorts = mkOption {
      type = bool;
      description = "Optionally open all relevant ports";
      default = true;
    };

    # XXX: should we assert that iotune isn't used in developer mode?
    # the documentation only talks about it in production deployment, but
    # there's also nothing that says you can't use it in development mode
    iotune = {
      enable = mkEnableOption "redpanda iotune";
      # XXX: should this just use configDir?
      location = mkOption {
        type = path;
        description = "Runtime path for io-config.yaml";
        default = "/etc/redpanda/io-config.yaml";
      };
      file = mkOption {
        type = nullOr path;
        description = "Pre-generated iotune config";
        default = null;
      };
    };

    admin = mkOption {
      description = "Superuser credentials";
      default = null;
      type = nullOr (submodule {
        options = {
          username = mkOption {
            type = str;
            default = "admin";
          };
          password = mkOption {
            type = path;
            description = "Password file";
          };
          saslMechanism = mkOption {
            type = enum [ "scram-sha-512" "scram-sha-256" ];
            default = "scram-sha-256";
          };
        };
      });
    };

    autoRestart = mkOption {
      type = bool;
      description = ''
        Restart local redpanda process if 
        1. the redpanda config, binary, etc change
        2. the cluster config needs a restart

        If this is false, you will need to manually put nodes in maintenance
        mode and restart them when applying changes.
      '';
      default = true;
    };

    nodeName = mkOption {
      type = str;
      default = config.networking.hostName;
      description = "The name of this node inside services.redpanda.cluster.nodes";
    };

    cluster = {
      nodes = mkOption {
        type = attrsOf clusterEntryDefinition;
        description = ''Description of the full cluster

          This field is a bit unusual, as it must be the same across all the nodes
          of a cluster, and thus across all the nixos configurations used.
          The best way to define it is into a separate, always included module.

          These fields must be static, or at least constant w.r.t. the current node
          `config`. For example, you cannot use `config.network.fqdn` to set the
          address.
          '';
        default = { };
        example = ''
          {
            alpha = {
              rpc_api.address = "0.0.0.0";
              advertised_rpc_api.addresss = "alpha.somewhere.com";
              advertised_kafka_api.addresss = "alpha.somewhere.com";
            };
            beta = {
              rpc_api.address = "0.0.0.0";
              advertised_rpc_api.addresss = "beta.somewhere.com";
              advertised_kafka_api.addresss = "beta.somewhere.com";
            };
            gamma = {
              rpc_api.address = "0.0.0.0";
              advertised_rpc_api.addresss = "gamma.somewhere.com";
              advertised_kafka_api.addresss = "gamma.somewhere.com";
            };
            # ...
          }
        '';
      };

      settings = mkOption {
        type = yaml.type;
        description = ''Cluster configuration properties

        Reference: https://docs.redpanda.com/docs/reference/cluster-properties/
        '';
        default = { };
      };
    };

    settings = mkOption {
      type = yaml.type;
      description = ''Broker configuration properties

      Will merge with default configuration, and tuned on startup.
      Reference: https://docs.redpanda.com/docs/reference/node-configuration-sample/
      '';
      default = { };
    };
  };

  config = mkIf cfg.enable {

    assertions = [{
      assertion = cfg.iotune.file != null -> lib.hasPrefix "/etc/" cfg.iotune.location;
      message = "If the redpanda option `iotune.file` is set, the corresponding `iotune.location` setting must be within `/etc/`";
    }];

    services.redpanda.settings = mkMerge [
      # Reuse config for this nodeName in the cluster config.
      # TODO: should we assert that the current node is in the cluster? This seems most likely to be a mistake.
      #       maybe they can set nodeName = null; to opt out
      { redpanda = (removeAttrs (cfg.cluster.nodes.${cfg.nodeName} or { }) [ "seed" ]); }
      {
        # TODO: should we import ${redpanda.src}/conf/redpanda.yaml instead of reproducing that information here?
        redpanda = {
          data_directory = mkDefault "${cfg.configDir}/data";
          rpc_server = { address = mkDefault "127.0.0.1"; port = mkDefault 33145; };
          advertised_rpc_api = {
            address = mkDefault "0.0.0.0";
            port = mkDefault cfg.settings.redpanda.rpc_server.port;
          };
          kafka_api = mkDefault [
            { address = "0.0.0.0"; port = 9092; }
          ];
          advertised_kafka_api = mkDefault [
            { address = "0.0.0.0"; port = 9092; }
          ];
          admin = mkDefault [
            { address = "127.0.0.1"; port = 9644; }
          ];
          developer_mode = mkDefault false;
          empty_seed_starts_cluster = mkDefault (cfg.cluster.nodes == { });
          seed_servers = mkDefault
            (mapAttrsToList
              (_: node: { host = node.advertised_rpc_api; })
              (filterAttrs (_: v: v.seed) cfg.cluster.nodes));
        };
        rpk = {
          coredump_dir = mkDefault "${cfg.configDir}/coredump";
          overprovisioned = mkDefault false; # Set true for dev mode
        };
        pandaproxy.pandaproxy_api = mkDefault [
          { address = "0.0.0.0"; port = 8082; }
        ];
        schema_registry.schema_registry_api = mkDefault [
          { address = "0.0.0.0"; port = 8081; }
        ];
      }
    ];

    environment.systemPackages = [ cfg.packages.client cfg.packages.server ];
    networking.firewall.allowedTCPPorts = mkIf cfg.openPorts portsToOpen;
    environment.etc = lib.mkIf (cfg.iotune.enable && cfg.iotune.file != null) {
      ${removePrefix "/etc/" cfg.iotune.location}.source = cfg.iotune.file;
    };

    systemd.slices.redpanda = {
      description = "Slice used to run Redpanda and rpk. Maximum priority for IO and CPU";
      before = [ "slices.target" ];
      sliceConfig = {
        MemoryAccounting = "true";
        IOAccounting = "true";
        CPUAccounting = "true";
        IOWeight = 1000;
        CPUWeight = 1000;
        MemoryMin = "2048M";
      };
    };

    systemd.services.redpanda-setup = {
      description = "Redpanda Setup";
      wantedBy = [ "redpanda.service" ];
      after = [ "network-online.target" ];
      requires = [ "local-fs.target" "network-online.target" ];
      restartTriggers = [ (builtins.toJSON config.systemd.units."redpanda.service".text) ];

      path = [
        cfg.packages.client
        cfg.packages.server
        pkgs.which
        pkgs.hwloc
        pkgs.util-linux
        pkgs.inetutils
        pkgs.gawk
      ];
      script = ''
        set -euo pipefail

        mkdir -p /opt
        ln -sfn ${cfg.packages.server} /opt/redpanda

        mkdir -p ${cfg.configDir}
        mkdir -p ${brokerCfg.redpanda.data_directory}
        cp ${brokerYaml} ${cfg.configDir}/redpanda.yaml
        cp ${clusterYaml} ${cfg.configDir}/.bootstrap.yaml

        ${rpkCmd} redpanda tune all --verbose
        ${lib.optionalString (cfg.iotune.enable && cfg.iotune.file == null) ''
            if ! [ -f ${cfg.iotune.location} ]; then
              mkdir -p $(dirname ${cfg.iotune.location})
              ${rpkCmd} iotune --out ${cfg.iotune.location}
            fi
          ''
        }

        # if redpanda is already running...
        # 1. try to apply new cluster config (this saves a restart later)
        # 2. restart it after applying config changes
        if systemctl status redpanda.service; then
          ${rpkCmd} cluster health --exit-when-healthy
          ${rpkCmd} cluster config import -f ${clusterYaml} \
            || true # best attempt

          ${lib.optionalString cfg.autoRestart ''
              # get node id of current broker
              # TODO: crash loudly when we cannot reliably find it.
              node_id=$(${rpkCmd} cluster metadata | awk '$2~/^'"$(hostname)"'$/ { print $1 }')
              # strip possible trailing *
              node_id=''${node_id%\*}

              echo "Restarting redpanda (node id $node_id) automatically"
              # wait until we can enter maintenance mode (or timeout)
              # TODO: check that this is failing because another node is in maintenance mode
              tryMaintenanceMode() {
                ${rpkCmd} cluster health --exit-when-healthy
                ${rpkCmd} cluster maintenance enable $node_id --wait
              }
              while ! tryMaintenanceMode; do
                echo "another node is in maintenance mode. waiting..."
                sleep 10
              done
              ${rpkCmd} cluster health --exit-when-healthy
              systemctl restart redpanda.service
              # TODO: Wait for the node to actually join the cluster
              sleep 2
              ${rpkCmd} cluster health --exit-when-healthy
              ${rpkCmd} cluster maintenance disable $node_id
              echo "Finished redpanda restart (node id $node_id)"
          ''}
        fi
      ''; # Do we need to include disks to tune also (--disks flag)?
      environment = {
        START_ARGS = "--check=true";
        HOME = "/root";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "true";
        TimeoutStartSec = 900;
        KillMode = "process";
        SyslogLevelPrefix = "false";
      };
    };

    systemd.services.redpanda-config = {
      description = "Redpanda cluster config";
      wantedBy = [ "multi-user.target" ];
      after = [ "redpanda.service" ];
      path = [ cfg.packages.client pkgs.gawk pkgs.inetutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "true";
        TimeoutStartSec = 900;
        KillMode = "process";
      };
      script = ''
        set -euo pipefail

        tryImportClusterConfig() {
          ${rpkCmd} cluster health --exit-when-healthy
          ${rpkCmd} cluster config import -f ${clusterYaml} 2>&1
        }
        while ! out=$(tryImportClusterConfig); do
          if [[ "$out" == *'no leader controller elected in the cluster'* ]]; then
            echo "WARNING: No leader controller elected while setting cluster configuration. This can happen if multiple servers are deployed simultaneously. Trying again."
            sleep 10
          else
            echo "$out"
            exit 1
          fi
        done

        ${
          lib.optionalString (cfg.admin != null) ''
            ${rpkCmd} acl user delete ${cfg.admin.username}
            ${rpkCmd} acl user create ${cfg.admin.username} -p $(cat ${cfg.admin.password}) --mechanism ${cfg.admin.saslMechanism}
          ''
        }

        echo "Cluster config status"
        ${rpkCmd} cluster config status

        need_restart=$(${rpkCmd} cluster config status | awk '$3~/true/ { ORS = " "; print $1 }')
        if [ -n "$need_restart" ]; then
          echo "WARNING: Have to restart these nodes to complete cluster config update: $need_restart"

          ${lib.optionalString cfg.autoRestart ''
            # get node id of current broker
            node_id=$(${rpkCmd} cluster metadata | awk '$2~/^'"$(hostname)"'$/ { print $1 }')
            # strip possible trailing *
            node_id=''${node_id%\*}

            # NOTE: for some reason they don't always need to all be restarted.
            # Here we check if the current node needs a restart.
            if [[ "$need_restart" = *"$node_id"* ]]; then
              echo "Restarting redpanda on this broker (node id $node_id) automatically"
              # wait until we can enter maintenance mode (or timeout)
              # TODO: check that this is failing because another node is in maintenance mode
              while ! ${rpkCmd} cluster maintenance enable $node_id --wait; do
                echo "another node is in maintenance mode. waiting..."
                sleep 10
              done
              ${rpkCmd} cluster health --exit-when-healthy
              systemctl restart redpanda.service
              ${rpkCmd} cluster health --exit-when-healthy
              ${rpkCmd} cluster maintenance disable $node_id
            fi
          ''}
        fi
      '';
      environment = {
        HOME = "${cfg.configDir}"; # rpk doesn't work without HOME
      };
    };

    systemd.services.redpanda = {
      description = "Redpanda, the fastest queue in the West.";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "network-online.target" "redpanda-setup.service" ];
      requires = [ "local-fs.target" "network-online.target" ];

      # redpanda needs to be restarted very carefully. we do so in redpanda-config
      restartIfChanged = false;

      serviceConfig = {
        Type = "notify";
        TimeoutStartSec = 900;
        ExecStart = "${cfg.packages.client}/bin/rpk redpanda start $START_ARGS $CPUSET --config ${cfg.configDir}/redpanda.yaml --install-dir ${cfg.packages.server}";
        ExecStop = "${cfg.packages.client}/bin/rpk redpanda stop --timeout 5s --config ${cfg.configDir}/redpanda.yaml";
        TimeoutStopSec = "11s";
        KillMode = "process";
        Restart = "on-abnormal";
        # User = "redpanda";  # From recommended deployment we should run as redpanda user
        OOMScoreAdjust = "-950";
        SyslogLevelPrefix = "false";
        Slice = "redpanda.slice";
        AmbientCapabilities = "CAP_SYS_NICE";
      };
      environment = {
        START_ARGS = "--check=true";
        HOME = "${cfg.configDir}";
      };
    };
  };
}
