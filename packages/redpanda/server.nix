{ stdenv
  # dependencies
, abseil-cpp
, avro-cpp
, base64
, boost
, ccache
, cmake
, crc32c
, croaring
, ctre
, curl
, dpdk
, git
, hdr-histogram
, lib
, libxml2
, llvmPackages
, ninja
, p11-kit
, pkg-config
, procps
, protobuf
, python3
, rapidjson
, re2
, redpanda_src
, redpanda_version
, seastar
, seastar_ref
, snappy
, unzip
, valgrind
, writeShellScriptBin
, xxHash
, zip
, zstd
}:

let
  kafka-codegen-venv = python3.withPackages (ps: [
    ps.jinja2
    ps.jsonschema
  ]);
in
stdenv.mkDerivation rec {
  pname = "redpanda-server";
  version = redpanda_version;
  src = redpanda_src;

  postUnpack = ''
    if ! grep "${seastar_ref}" -r ; then
      echo "Seastar ref must align with redpanda sources"
      exit 1
    fi
  '';

  preConfigure = ''
    # setup sccache
    export CCACHE_DIR=$TMPDIR/sccache-redpanda
    mkdir -p $CCACHE_DIR
  '';

  shellHook = ''
    # To ensure that shells use the same ccache cache
    export TMPDIR=/tmp
  '';

  patches = [ ./redpanda.patch ];

  postPatch = ''
    # Fix 'error: use of undeclared identifier 'roaring'; did you mean 'Roaring
    #      qualified reference to 'Roaring' is a constructor name rather than a type in this context'
    substituteInPlace \
        ./src/v/storage/compacted_offset_list.h \
        ./src/v/storage/compaction_reducers.cc \
        ./src/v/storage/compaction_reducers.h \
        ./src/v/storage/segment_utils.h \
        ./src/v/storage/segment_utils.cc \
        --replace 'roaring::Roaring' 'Roaring'

    patchShebangs ./src/v/rpc/rpc_compiler.py
  '';

  hardeningDisable = [ "fortify" ];

  doCheck = false;

  nativeBuildInputs = [
    (python3.withPackages (ps: [ ps.jinja2 ]))
    (writeShellScriptBin "kafka-codegen-venv" "exec -a $0 ${kafka-codegen-venv}/bin/python3 $@")
    ccache
    cmake
    curl
    git
    llvmPackages.llvm
    ninja
    pkg-config
    procps
    seastar
    unzip
    zip
  ];

  cmakeFlags = [
    "-DREDPANDA_DEPS_SKIP_BUILD=ON"
    "-DRP_ENABLE_TESTS=OFF"
    "-Wno-dev"
    "-DGIT_VER=${version}"
    "-DGIT_CLEAN_DIRTY=\"\""
  ];

  buildInputs = [
    abseil-cpp
    avro-cpp
    base64
    boost
    crc32c
    croaring
    ctre
    dpdk
    hdr-histogram
    libxml2
    p11-kit
    protobuf
    rapidjson
    re2
    seastar
    snappy
    valgrind
    xxHash
    zstd
  ];

  meta = with lib; {
    description = "Kafka-compatible streaming platform.";
    license = licenses.gpl3;
    longDescription = ''
      Redpanda is a Kafka-compatible streaming data platform that is
      proven to be 10x faster and 6x lower in total costs. It is also JVM-free,
      ZooKeeper-free, Jepsen-tested and source available.
    '';
    homepage = "https://redpanda.com/";
    maintainers = with maintainers; [ avakhrenev happysalada ];
    platforms = platforms.linux;
  };
}
