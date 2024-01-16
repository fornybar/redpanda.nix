{ pkgs, self }:
let
  python = pkgs.python310.withPackages (ps: with ps; [ requests aiokafka ]);
  rebuildableTest = import ./rebuildableTest.nix pkgs;
in
rebuildableTest {
  name = "test-redpanda";
  nodes = {
    server = {
      imports = [ self.nixosModules.redpanda ]; #redpanda-console doesn't work without internet
      virtualisation.diskSize = 10 * 1024; # 10GiB
      virtualisation.memorySize = 2 * 1024; # 2GiB
      services.redpanda = {
        enable = true;
        broker.settings = {
          redpanda = {
            developer_mode = true;
            empty_seed_starts_cluster = true;
          };
          rpk.overprovisioned = false;
        };
      };
    };

    prodserver = {
      imports = [ self.nixosModules.redpanda ];
      # Production settings are more strict about available ressources
      virtualisation.diskSize = 10 * 1024; # 10GiB
      virtualisation.memorySize = 5 * 1024; # 5GiB
      services.redpanda = {
        enable = true;
        # I don't think there's a way to test this since
        # - not specifying `file` makes it take a really long time
        # - specifying `file` is dependent on each person's computer
        # but all we do is start up the prodserver, so maybe the latter is fine.
        # iotune = {
        #   enable = true;
        #   file = ./io-config.yaml;
        # };
        broker.settings.developer_mode = false;
        # XXX: what are these settings? do they do anything? I couldn't find them in the documentation
        broker.settings.rpk = {
          ballast_file_size = "1B";
          tune_net = true;
          tune_disk_scheduler = true;
          tune_disk_nomerges = true;
          tune_disk_write_cache = true;
          tune_disk_irq = true;
          tune_cpu = true;
          tune_aio_events = true;
          tune_clocksource = true;
          tune_swappiness = true;
          tune_ballast_file = true;
        };
      };
    };

    authserver = {
      imports = [ self.nixosModules.redpanda self.nixosModules.redpanda-acl ];
      virtualisation.diskSize = 10 * 1024; # 10GiB
      virtualisation.memorySize = 2 * 1024; # 2GiB

      services.redpanda = {
        enable = true;
        admin.password = builtins.toFile "admin.password" "admin";
        broker.settings = {
          redpanda = {
            developer_mode = true;
            empty_seed_starts_cluster = true;
            kafka_api = [
              { address = "0.0.0.0"; port = 9092; authentication_method = "sasl"; }
            ];
            advertised_kafka_api = [
              # Required for being accessible from client
              { address = "authserver"; port = 9092; }
            ];
          };
          pandaproxy.pandaproxy_api = [
            { address = "0.0.0.0"; port = 8082; authentication_method = "http_basic"; }
          ];
          schema_registry.schema_registry_api = [
            { address = "0.0.0.0"; port = 8081; authentication_method = "http_basic"; }
          ];
          rpk.overprovisioned = false;
        };
        cluster.settings = {
          kafka_enable_authorization = true;
          superusers = [ "admin" ];
          auto_create_topics_enabled = true;
        };
      };

      # SEE: https://github.com/NixOS/nixpkgs/issues/62155
      systemd.services.redpanda-acl.serviceConfig.RemainAfterExit = true;
      services.redpanda-acl = {
        enable = true;
        kafka = {
          bootstrapServer = "0.0.0.0:9092";
          username = "admin";
          password = builtins.toFile "admin.password" "admin";
        };
        acls = {
          user-1 = {
            userPasswordFile = builtins.toFile "user-1.password" "userPass1";
            acls = [
              {
                topic = [ "raw" ];
                operation = [ "read" "write" ];
                resource-pattern-type = "prefixed";
              }
            ];
          };
          user-2 = {
            userPasswordFile = builtins.toFile "user-2.password" "userPass2";
            acls = [
              {
                topic = [ "raw" ];
                operation = [ "read" ];
                resource-pattern-type = "prefixed";
              }
              {
                topic = [ "topic_1" "topic_2" ];
                group = [ "group_2" "group_3" ];
                operation = [ "Describe" ];
              }
            ];
          };
        };
      };
    };

    client = {
      environment = {
        systemPackages = [ python ];
        variables = {
          # For ./produce.py
          REDPANDA_API_URL = "http://server:8082";

          # For ./auth.py
          REDPANDA_PANDAPROXY_URL = "http://authserver:8082";
          REDPANDA_SCHEMA_REGISTRY_URL = "http://authserver:8081";
          REDPANDA_KAFKA_SERVER = "authserver:9092";
        };
      };
    };
  };

  testScript = ''

    print("--> Starting testScript")
    server.start()
    client.start()

    with subtest("Simple produce/consume test"):
      server.wait_for_unit("redpanda.service")
      server.wait_until_succeeds("rpk cluster health --exit-when-healthy --watch", timeout=100)
      server.succeed("rpk topic create hei", timeout=100)
      client.succeed("python ${./produce.py} 1>&2", timeout=100)

    server.shutdown()
    authserver.start()

    with subtest("Test authentication enabled"):
      authserver.wait_for_unit("redpanda-acl.service")
      authserver.wait_until_succeeds("rpk cluster health --exit-when-healthy --watch", timeout=100)
      client.succeed("python ${./auth.py} 1>&2", timeout=100)

    with subtest("Test ACL creation"):
      authserver.wait_for_console_text("Finished creating ACLs")
      s,aclLog = authserver.execute("journalctl -u redpanda-acl.service")
      assert "7 ACLs to be created" in aclLog, "Incorrect number of ACLs to be created"
      assert "User:user-1" in aclLog, "No ACLs created for user-1"
      assert "User:user-2" in aclLog, "No ACLs created for user-2"

    authserver.shutdown()

    prodserver.start() # May complain about having too little memory, so we run it alone
    with subtest("Production mode setup test"):
      prodserver.wait_for_unit("redpanda-setup.service")
  '';
}
