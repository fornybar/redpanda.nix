{ self, pkgs }:
{
  nixos-test-redpanda = import ./redpanda.nix {
    inherit pkgs self;
    redpanda-server = pkgs.redpanda-server;
    redpanda-client = pkgs.redpanda-client;
  };

  nixos-test-redpanda-bin = import ./redpanda.nix {
    inherit pkgs self;
    redpanda-server = pkgs.redpanda-server-bin;
    redpanda-client = pkgs.redpanda-client-bin;
  };

  nixos-test-cluster = import ./cluster.nix {
    inherit pkgs self;
    redpanda-server = pkgs.redpanda-server;
    redpanda-client = pkgs.redpanda-client;
  };

  nixos-test-cluster-bin = import ./cluster.nix {
    inherit pkgs self;
    redpanda-server = pkgs.redpanda-server-bin;
    redpanda-client = pkgs.redpanda-client-bin;
  };
}
