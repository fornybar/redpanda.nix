final: prev: {
  # Use redpanda builds
  redpanda-bin = prev.callPackage ./redpanda-bin { };
  redpanda-server-bin = final.redpanda-bin;
  redpanda-client-bin = final.redpanda-bin;
  redpanda-console-bin = prev.callPackage ./redpanda-console { };

  # Redpanda from source
  inherit (prev.callPackages ./redpanda { })
    redpanda-server
    redpanda-client
    seastar
    ;
}
