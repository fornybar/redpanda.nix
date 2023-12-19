{ pkgs, self }:
let
  rebuildableTest = import ./rebuildableTest.nix pkgs;

  # to run interactively, `nix build .#checks.x86_64-linux.<test>.driverInteractive && ./result/bin/nixos-test-driver`
  # to push changes to the configuration, run `nix build .#checks.x86_64-linux.<test>.rebuildScript && ./result`

  baseConfig = { lib, ... }: {
    imports = [ self.nixosModules.redpanda ];

    virtualisation.diskSize = 10 * 1024; # 10GiB
    virtualisation.memorySize = 2 * 1024; # 2GiB

    services.redpanda = {
      enable = true;
      autoRestart = true;
      cluster.nodes = {
        server0 = {
          advertised_rpc_api.address = "server0";
          advertised_kafka_api = [{ address = "server0"; }];
        };
        server1 = {
          advertised_rpc_api.address = "server1";
          advertised_kafka_api = [{ address = "server1"; }];
        };
        server2 = {
          advertised_rpc_api.address = "server2";
          advertised_kafka_api = [{ address = "server2"; }];
        };
      };
      broker.settings = {
        redpanda = {
          rpc_server.address = "0.0.0.0";
          developer_mode = true;
          empty_seed_starts_cluster = false;
        };
        rpk.overprovisioned = false;
      };
    };
    specialisation.trigger_restart.configuration = {
      # change a bunch of stuff that in theory needs a restart, because in practice a lot of it doesn't
      services.redpanda.cluster.settings = {
        kafka_connection_rate_limit = lib.mkForce 20;
        aggregate_metrics = true;
        disable_public_metrics = true;
        internal_topic_replication_factor = 1;
        enable_transactions = false;
        tm_sync_timeout_ms = "100000";
        tx_timeout_delay_ms = "10000";
      };
    };
  };

  trigger_restart = "/run/current-system/specialisation/trigger_restart/bin/switch-to-configuration test";

  test = rebuildableTest {
    name = "test-cluster";
    nodes = {
      server0 = {
        imports = [ baseConfig ];
      };
      server1 = {
        imports = [ baseConfig ];
      };
      server2 = {
        imports = [ baseConfig ];
      };

      client = {
        environment.systemPackages = [ pkgs.redpanda ];
        nix.extraOptions = ''
          extra-experimental-features = nix-command flakes
        '';
        environment = {
          variables = {
            REDPANDA_BROKERS = "server0:9092,server1:9092,server2:9092";
          };
        };
      };
    };

    testScript = ''
      print("--> Starting testScript")
      start_all()

      with subtest("Cluster produce/consume test"):
        server0.wait_for_unit("redpanda.service")
        server1.wait_for_unit("redpanda.service")
        server2.wait_for_unit("redpanda.service")
        server0.wait_until_succeeds("rpk cluster health --exit-when-healthy", timeout=100)
        server1.wait_until_succeeds("rpk cluster health --exit-when-healthy", timeout=100)
        server2.wait_until_succeeds("rpk cluster health --exit-when-healthy", timeout=100)
        client.succeed("rpk topic create hei --brokers 'server0:9092'", timeout=20)
        client.succeed("echo 'foo' | rpk topic produce hei --brokers 'server1:9092'", timeout=20)
        client.succeed("rpk topic consume hei -n 1 --brokers 'server2:9092'", timeout=20)

      with subtest("Reproduction factor 3"):
        client.succeed("rpk topic create hei2 --brokers 'server0:9092' -r 3", timeout=20)
        client.succeed("echo 'foo' | rpk topic produce hei2 --brokers 'server1:9092'", timeout=20)
        client.succeed("rpk topic consume hei2 -n 1 --brokers 'server2:9092'", timeout=20)

      with subtest("Restart cluster"):
        # XXX: is there a better way to run a command without waiting for it to finish?
        # XXX: this is stochastic. not good for a test. can we reliably make them interfere with each other?
        # gotta login first

        # switch them all to the specialisation at once, triggering simultaneous cluster config setting
        for s in [ server0, server1, server2 ]:
          # FIXME: this is a nicer way to run things in parallel. you can find it in other nixos tests. it does seem to run the commands in parallel, but it doesn't trigger the error.
          # s.execute('(${trigger_restart}; echo $? >/rebuild_status) >&2 &')
          s.send_chars("root\n")
          s.send_chars("(${trigger_restart}; echo $? >/rebuild_status)\n")

        for s in [ server0, server1, server2 ]:
          s.wait_for_file('/rebuild_status')
          # test rebuilds succeeded
          s.succeed('exit $(</rebuild_status)')
          # sanity check we're running the specialisation
          s.succeed('test "$(ls /run/current-system/specialisation)" = ""')
          # sanity check redpanda-config succeeded
          s.wait_for_unit("redpanda-config.service")
          # cluster back to healthy
          s.wait_until_succeeds("rpk cluster health --exit-when-healthy", timeout=100);
    '';
  };
in
test
