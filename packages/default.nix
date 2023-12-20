{ callPackage, callPackages }:
rec {
  redpanda-bin = callPackage ./redpanda-bin { };

  redpanda-server-bin = redpanda-bin;
  redpanda-client-bin = redpanda-bin;

  redpanda-console-bin = callPackage ./redpanda-console { };

  inherit (callPackages ./redpanda { })
    redpanda-server
    redpanda-client
    seastar
    ;
}
