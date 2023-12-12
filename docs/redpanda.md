# Deploying on NixOS

You can deploy Redpanda on a NixOS system. This allows simpler configuration of some services, and tighter integration with other parts of the system's configuration, but prevents imperative changes to the configuration. NixOS takes a different approach to service configuration than most other operating systems. Rather than configure each service independently and somewhat imperatively, there is one declarative global configuration for your system written in [the Nix language](https://nixos.org/manual/nix/unstable/language/index.html) that configures each of the separate services when it's activated. This allows reproducible configuration with a common interface, but some of the other Redpanda documentation will have to be [reinterpreted](#interpreting-other-documentation) to work with NixOS.

[XXX: figure out a way to work this into the prose.]
More documentation for Redpanda's NixOS options can be found [here](https://search.nixos.org/options?channel=23.05&from=0&size=50&sort=relevance&type=packages&query=services.redpanda)


# Prerequisites

## Hardware and software

The same prerequisites for a any linux environment are recommended for NixOS.

- Operating system
  - The latest version of Redpanda was added in Nixpkgs/NixOS [XXX: fill this in when it's in]. Earlier versions of Nixpkgs/NixOS may support earlier versions of Redpanda.

- CPU and memory
  - A minimum of three physical nodes or virtual machines are required. [XXX: This is only for a cluster? But their existing docs seem wrong.]
  - Two physical (not virtual) cores are required. Four physical cores are strongly recommended.
  - x86_64 (Westmere or newer) and AWS Graviton family processors are supported.

- Storage
  - An XFS or ext4 file system for the data directory of Redpanda (/var/lib/redpanda/data) or the Tiered Storage cache. XFS is highly recommended. NFS is not supported.
  - Locally-attached NVMe devices. RAID-0 is required if you use multiple disks.
  - Ephemeral cloud instance storage is only recommended in combination with Tiered Storage or for Tiered Storage cache. Without Tiered Storage, attached persistent volumes (for example, EBS) are recommended.

- Object storage providers for Tiered Storage
  - Amazon Simple Storage Service (S3)
  - Google Cloud Storage (GCS), using the Google Cloud Platform S3 API
  - Azure Blob Storage (ABS)

- Networking
  - Minimum 10 GigE

See [Manage Disk Space](https://docs.redpanda.com/current/manage/cluster-maintenance/disk-utilization/) for guidelines on cluster creation.

# TCP/IP ports

Redpanda uses the following default ports:

| Port | Purpose |
| ---- | ------- |
| 9092 | Kafka API |
| 8082 | HTTP Proxy |
| 8081 | Schema Registry |
| 9644 | Admin API and Prometheus |
| 33145 | internal RPC |

By default ports that need to be opened will be automatically in the NixOS firewall. To disable this behaviour set `services.redpanda.openPorts = false;`

# Deploy for development

Deploying for development is as simple as enabling the redpanda service in your nixos configuration, and as always switching to that configuration. You can also enable the redpanda console.

```nix
{
  services.redpanda.enable = true;
  services.redpanda-console.enable = true;
}
```

```bash
nixos-rebuild switch
```

# Deploy a cluster

To configure your broker as part of a cluster, you can specify a list of cluster nodes, and where they can be found. This setting should be the same across all nodes in a cluster, which can be done most easily by factoring the common configuration into a separate file, and importing into each machine's configuration. All cluster settings go here as well.

```nix
# cluster_configuration.nix
{
  services.redpanda.cluster = {
    nodes = {
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
        seed = false;
        rpc_api.address = "0.0.0.0";
        advertised_rpc_api.addresss = "gamma.somewhere.com";
        advertised_kafka_api.addresss = "gamma.somewhere.com";
      };
      # ...
    };
    settings = {
      default_topic_replications = 3;
    };
  };
}

# alpha.nix
{
  imports = [ ./cluster_configuration.nix ];
  services.redpanda.nodeName = "alpha"; # by default uses the hostname
}

# beta.nix
{
  imports = [ ./cluster_configuration.nix ];
  services.redpanda.nodeName = "beta"; # by default uses the hostname
}

# gamma.nix
{
  imports = [ ./cluster_configuration.nix ];
  services.redpanda.nodeName = "gamma"; # by default uses the hostname
}

```

## Config synchronization

Redpanda ensures that cluster nodes always have the same cluster config. When a NixOS machine is deployed, it will apply its new cluster config not only to itself but to all cluster members. This means that the configuration actually present on the machine can get out of sync with the one defined by NixOS. As long as machines are kept up-to-date and deployed together, this should not be an issue.

- [TODO: leaderNode is not currently implemented]

However, another model for dealing with this is to designate one machine as the cluster leader by setting

```
  services.redpanda.cluster.leaderNode = "alpha";
```

The cluster configuration set on that machine will then be pushed to all members, and the cluster configurations they define are ignored. This clearly designates where the configuration is coming from, so that there is no ambiguity where things can get out of sync.

## Restarting

The option `services.redpanda.cluster.autoRestart` sets redpanda to restart if needed when the cluster configuration is changed (if the broker configuration is changed, it will always require a restart).

If the `leaderNode` is not set, each node will restart itself when deployed. IF `leaderNode` is set, then the leader will restart the nodes in sequence when it sets a new configuration.

- [XXX: how do we get the leader to restart the other machines?]
   - put them in maintenance mode, and have them poll whether they are in maintenance mode and if so restart


- [XXX: is there a reason we currently have `developer_mode` off by default? this is the opposite of what redpanda docs state]
- [XXX: Do we want to include instructions for a multi-server deployment system like colmena/deploy-rs? The reason to do this is it simplifies the configuration for clusters, the problem is that there's no one blessed option, and so it's a little weird to pick one in the official redpanda docs.]

# Production

To switch to production mode set the `developer_mode` option to `false`.

```nix
{
  services.redpanda.settings.redpanda.developer_mode = false;
}
```

## Optional: benchmark your SSD

On taller machines, Redpanda recommends benchmarking your SSD. This can be done with [rpk iotune](https://docs.redpanda.com/current/reference/rpk/rpk-iotune/). You only need to run this once.

You can tell NixOS to run `rpk iotune` at startup if it hasn't already been run by setting
```nix
{
  services.redpanda.iotune.enable = true;
}
```

Once the file is generated (either by NixOS, or by running `rpk iotune` manually), you can tie it into your NixOS configuration by setting

```nix
{
  services.redpanda.iotune.enable = true;
  services.redpanda.iotune.file = ./path/to/io-config.yaml;
}
```

Remember to delete the original `/etc/redpanda/io-config.yaml` so that NixOS can manage the file itself.

NOTE: `io-config.yaml` is hardware-specific. Do not use one file in common between multiple machines' configurations.

# verify the installation

To verify that the Redpanda cluster is up and running, use rpk to get information about the cluster:

```bash
rpk cluster info
```

If topics were initially created in a test environment with a replication factor of 1, use rpk topic alter-config to change the topic replication factor:

```bash
rpk topic alter-config [TOPICS...] --set replication.factor=3
```

To create a topic:

```bash
rpk topic create panda
```

# Custom Deployment


## Configure the seed servers

If you've configured `services.redpanda.cluster` as described [above](#deploying-a-cluster), it will set `empty_seed_starts_cluster`, and populate the `seed_servers` list, as well as configuring advertised api addresses. You can instead manually configure these options.

Seed servers help new brokers join a cluster by directing requests from newly-started brokers to an existing cluster. The `seed_servers` broker configuration property controls how Redpanda finds its peers when initially forming a cluster. It is dependent on the `empty_seed_starts_cluster` broker configuration property.

Starting with Redpanda version 22.3, you should explicitly set `empty_seed_starts_cluster` to `false` on every broker, and every broker in the cluster should have the same value set for `seed_servers`. With this set of configurations, Redpanda clusters form with these guidelines:

- When a broker starts and it is a seed server (its address is in the seed_servers list), it waits for all other seed servers to start up, and it forms a cluster with all seed servers as members.
- When a broker starts and it is not a seed server, it sends requests to the seed servers to join the cluster.

It is essential that all seed servers have identical values for the `seed_servers` list. Redpanda strongly recommends at least three seed servers when forming a cluster. Each seed server decreases the likelihood of unintentionally forming a split brain cluster. To ensure brokers can always discover the cluster, at least one seed server should be available at all times.

By default, for backward compatibility, `empty_seed_starts_cluster` is set to `true`, and Redpanda clusters form with the guidelines used prior to version 22.3:

- When a broker starts with an empty `seed_servers` list, it creates a single broker cluster with itself as the only member.
- When a broker starts with a non-empty `seed_servers` list, it sends requests to the brokers in that list to join the cluster.

You should never have more than one broker with an empty `seed_servers` list, which would result in the creation of multiple clusters.

An example configuration looks like

```nix
{
  services.redpanda.settings.redpanda = {
    empty_seed_starts_cluster = false;
    seed_servers = [
      {
        host = {
          address = "alpha.somewhere.com";
          port = 33145;
        };
      }
      {
        host = {
          address = "beta.somewhere.com";
          port = 33145;
        };
      }
    ];
  };
}
```

- customizations are all set via the nixos configuration

- besides the bootstrapping sections, this can be largely the same as the linux docs

## Configure broker IDs

Redpanda automatically generates unique IDs for each new broker. This means that you don’t need to include IDs in configuration files or worry about policies on `node_id` re-use.

If you choose to assign broker IDs, make sure to use a fresh `node_id` each time you add a broker to the cluster.

```nix
{
  services.redpanda.settings.node_id = 0;
}
```

::: caution
Never reuse broker IDs, even for brokers that have been decommissioned and restarted empty. Doing so can result in an inconsistent state. 
:::

## Upgrade considerations

- [XXX: We don't really have a story for how this happens on NixOS yet.]
- [XXX: redpanda version should be tied to `state_version`, since a manual step-by-step upgrade process is needed]
- [SEE: https://docs.redpanda.com/current/upgrade/rolling-upgrade]

Deployment automation should place each broker into maintenance mode and wait for it to drain leadership before restarting it with a newer version of Redpanda. For more information, see Upgrade.

If upgrading multiple feature release versions of Redpanda in succession, make sure to verify that each version upgrades to completion before proceeding to the next version. You can verify by reading the /v1/features Admin API endpoint and checking that cluster_version has increased.

Starting with Redpanda version 23.1, the /v1/features endpoint also includes a node_latest_version attribute, and installers can verify that the cluster has activated any new functionality from a previous upgrade by checking for cluster_version == node_latest_version.

# Interpreting other documentation

Most Redpanda documentation needs to be reinterpreted in the context of NixOS. Fortunately, a few simple rules cover most of it.

After any change to the NixOS configuration, one must run `nixos-rebuild switch` to activate the new configuration. This will take care of applying changes to the configuration, and restarting any services that need restarting. If the change affects a cluster, the change must be applied to the configuration of every broker in that cluster.

Any cluster configuration command `rpk cluster config ...` should instead be set in the nixos configuration as

```nix
{
  services.redpanda.cluster.settings = {
    # configuration goes here...
    # e.g.
    default_topic_replications = 3;
    enable_transactions = false;
    kafka_nodelete_topics = [ "audit" "consumer_offsets" ];
  };
}
```

Yaml configuration of broker properties will have to be renderered as a Nix attrset under the `services.redpanda.settings.broker` option. For example,

```yaml
# /etc/redpanda/redpanda.yml
crash_loop_limit: 10
dashboard_dir: /var/www/dashboard
```

becomes

```nix
# /etc/nixos/configuration.nix
{
  services.redpanda.settings = {
    crash_loop_limit = 10;
    dashboard_dir = "/var/www/dashboard";
  };
}
```

Any commands that interact with **data** (topics, messages, etc) as opposed to configuration, will work as-is.

One should be cautious around any imperative configuration command (e.g. `rpk iotune`). They may not work at all, they may work only until reboot, or they may work fine, but there is usually a more Nix-appropriate way of configuring them declaratively. This documentation should cover all of those cases. If something is missing, please report it here. [XXX: where?]

# notes

- [TODO: make a NixOS test for redpanda-console]
- [TODO: make a services.redpanda.console option, which configures redpanda-console according to the local redpanda configuration]

- [XXX: During bootstrapping, redpanda sets the IP addresses of the kafka API and the RPC server to the machine's internal IP, which it detects at runtime. Our current default is `0.0.0.0`, which seems to work anyways. Are we doing it wrong? This might be hard to do with a static configuration because IP addresses can be variable.]
  - If there's a static IP configured, we can probably detect and grab that. Dynamic IPs wouldn't be stable anyways so it's not clear if they're suited for a redpanda interface.

- [XXX: the docs state "It’s possible to change the seed servers for a short period of time after a cluster has been created." Is it **not** possible to change the seed servers a long time after the cluster has been created? What happens if you try? Do we need to guard against that in the NixOS configuration, or at least emit a warning?]

- [XXX: we should be careful about what configuration changes require a restart of the systemd service, and which ones should just reload the configuration]
