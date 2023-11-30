{ config, lib, pkgs, ... }:
with lib;
with types;

/**
 *
 *  ## Redpanda ACLs
 *
 *  The redpanda ACL module is used to define the acl rules we apply in a
 *  terraform like manner. This means that any ACLs that are not in the config
 *  will be destroyed upon redployment, while new ones will be created. One can
 *  still add new ACLs in the console manually, however upon redployment these
 *  will also be destroyed. See below config for an example ACL definition:
 *
 *  ```
 *    acls = {
 *      test_user = {
 *        acls = [
 *          {
 *            topic = [ "raw.test" ];
 *            group [ "cs_1" ]
 *            operation = ["read" ];
 *            resource-pattern-type = "prefixed";
 *          }
 *          {
 *            transactionalId = [ "tId_1" ];
 *            operation = ["write" ];
 *          }
 *        ];
 *      };
 *    };
 *  ```
 *
 *  The first ACL gives the principal `test_user` the ability to `read` from
 *  topics **prefixed** with `raw.test`. It grants the principal `test_user` the
 *  permission to consumer group `cs_1` the ability to `read` (in the case of a
 *  consumer group, this is e.g. commiting offsets) from topics this principal
 *  has rights to.
 *
 *  The second ACL grants the principal `test_user` the permission to use the
 *  transactional ID `tId_1` for producing messages to Kafka for topics this
 *  principal has rights to. This is relevant in the case we use kafka
 *  transactions in our producer set-up.
 *
 *  The `resource-pattern-type` governs whether we use prefixes or literal
 *  interpretations of the topics/groups.
 *
 *  A full set of the ACLs one can create is given here:
 *  [docs](https://docs.redpanda.com/docs/reference/rpk/rpk-acl/). Note that in
 *  the module we currently only allow for the following resources:
 *
 *  - Topic
 *  - Group
 *  - Transactional ID
 *
 */

let
  cfg = config.services.redpanda-acl;
  aclFile = builtins.toFile "acl-file" (builtins.toJSON cfg.acls);

  python = pkgs.python310.withPackages (ps: with ps; [ aiokafka loguru requests pandas ]);

  aclDefinition = submodule {
    options = {
      topic = mkOption {
        type = listOf str;
        default = [ ];
        description = "Topic to grant ACLs for";
      };
      group = mkOption {
        type = listOf str;
        default = [ ];
        description = "Groups to grant ACLs for";
      };
      transactionalId = mkOption {
        type = listOf str;
        default = [ ];
        description = "Transactional IDs to grant ACLs for";
      };
      cluster = mkOption {
        type = bool;
        default = false;
        description = "Whether or not to grant ACLs to cluster";
      };
      operation = mkOption {
        type = listOf str;
        description = "Which operations to allow";
      };
      resource-pattern-type = mkOption {
        type = enum [ "literal" "prefixed" ];
        default = "literal";
        description = "Pattern to use when matching resource names (literal or prefixed)";
      };
    };
  };

  aclType = submodule {
    options = {
      acls = mkOption {
        type = listOf aclDefinition;
        default = [ ];
        description = ''
          List of ACLs to grant to principal
        '';
      };
    };
  };

in
{
  options.services.redpanda-acl = {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable ACL provisioning";
    };
    kafka = mkOption {
      description = "Kafka credentials to authenticate RPK with";
      type = submodule {
        options = {
          kafkaBootstrapServer = mkOption {
            type = str;
            description = "Broker address to connect to";
          };
          kafkaUsername = mkOption {
            type = str;
            description = "Username for connection";
          };
          kafkaPassword = mkOption {
            type = path;
            description = "Path to file containing password for connection";
          };
        };
      };
    };
    acls = mkOption {
      type = attrsOf aclType;
      description = "Set of ACLs to grant. Name assigned to each subset is the name of user to which that ACL will be granted";
      default = { };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.redpanda-acl = {
      description = "ACL service";
      wantedBy = [ "multi-user.target" ];
      after = [ "redpanda.service" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.redpanda ];
      serviceConfig = {
        ExecStart = ''
          ${python.interpreter} ${./acl.py} ${aclFile} ${cfg.kafka.kafkaBootstrapServer} ${cfg.kafka.kafkaUsername} ${cfg.kafka.kafkaPassword}
        '';
      };
    };
  };
}


