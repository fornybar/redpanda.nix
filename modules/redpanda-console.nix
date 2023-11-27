{ config, lib, pkgs, ... }:
with lib;

let
  inherit (lib.attrsets) recursiveUpdate;

  cfg = config.services.redpanda-console;

  yaml = pkgs.formats.yaml { };

  consoleYaml = yaml.generate "redpanda-console.yaml" cfg.settings;
in
{
  options.services.redpanda-console = with types; {
    enable = mkEnableOption "Redpanda console";

    package = mkOption {
      type = package;
      # FIXME: doesn't actually exist. no default for now
      # default = pkgs.redpanda-console;
      defaultText = literalExpression "pkgs.redpanda-console";
      description = "Which Redpanda console package to use";
    };

    kafkaBrokers = mkOption {
      description = "Kafka brokers to connect to";
      default = [ ];
      type = listOf (submodule {
        options = {
          address = mkOption {
            type = str;
          };
          port = mkOption {
            type = port;
          };
        };
      });
    };

    port = mkOption {
      type = port;
      default = 8080;
      description = "Port to listen on";
    };

    openPorts = mkOption {
      type = bool;
      default = true;
      description = "Open port in firewall";
    };

    settings = mkOption {
      type = attrsOf anything;
      default = { };
      description = ''Redpanda console configuration properties

      Reference: https://docs.redpanda.com/docs/reference/console/config/
      '';
    };

    startupScript = mkOption {
      type = str;
      default = "";
      description = ''Run before starting console

      Can be used to set secret environment variable config.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings.kafka.brokers != "";
        message = "No Kafka brokers specified";
      }
    ];

    services.redpanda-console.settings = {
      kafka.brokers = lib.mkDefault (concatStringsSep ","
        (map (x: x.address + ":" + toString x.port) cfg.kafkaBrokers));
      server.listenPort = lib.mkDefault cfg.port;
    };


    networking.firewall.allowedTCPPorts = mkIf cfg.openPorts [ cfg.port ];

    systemd.services.redpanda-console = {
      description = "Redpanda Console, UI for Kafka/Redpanda.";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      documentation = [ "https://docs.redpanda.com" ];
      script = ''
        ${cfg.startupScript}
        ${cfg.package}/bin/redpanda-console -config.filepath ${consoleYaml}
      '';
      serviceConfig = {
        Restart = "on-failure";
        TimeoutStartSec = 120;
        RestartSec = 5;
      };
    };
  };
}
