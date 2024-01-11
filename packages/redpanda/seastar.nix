{ boost
, c-ares
, cmake
, cryptopp
, fetchFromGitHub
, fmt_8
, gnutls
, hwloc
, lib
, libsystemtap
, libtasn1
, liburing
, libxfs
, lksctp-tools
, llvmPackages
, lz4
, ninja
, numactl
, openssl
, pkg-config
, python3
, ragel
, seastar_version
, valgrind
, yaml-cpp
}:

llvmPackages.libcxxStdenv.mkDerivation {
  pname = "seastar";
  version = seastar_version;
  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "seastar";
    rev = "v${seastar_version}";
    sha256 = "sha256-qABmEiDUCpxPETzb4WyIjz5ogcJNX2EaYx0zirB98xc=";
  };

  # Breaks exported cmakeConfig include paths
  #outputs = [ "out" "dev" ];

  # Seastar does a lot of finicky things, and triggers fortify errors.
  # See https://github.com/redpanda-data/seastar/blob/d1d5354b9e271041e5f5bda9d3e163adfdd825ab/CMakeLists.txt#L836-L841
  hardeningDisable = [ "fortify" ];

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    ninja
    openssl
    pkg-config
    python3
    ragel
  ];

  buildInputs = [
    libsystemtap
    libxfs
  ];

  propagatedBuildInputs = [
    boost
    c-ares
    gnutls
    cryptopp
    fmt_8
    hwloc
    libtasn1
    liburing
    lksctp-tools
    lz4
    numactl
    valgrind
    yaml-cpp
  ];

  postPatch = ''
    patchShebangs ./scripts/seastar-json2code.py
  '';

  cmakeFlags = [
    "-DSeastar_EXCLUDE_DEMOS_FROM_ALL=ON"
    "-DSeastar_EXCLUDE_TESTS_FROM_ALL=ON"

    # from redpanda/cmake/oss.cmake.in
    # NOTE: redpanda expects to be building seastar itself, whereas we build it in a separate package.
    "-DSeastar_CXX_FLAGS=-Wno-error"
    "-DSeastar_DPDK=OFF"
    "-DSeastar_DEMOS=OFF"
    "-DSeastar_DOCS=OFF"
    "-DSeastar_TESTING=OFF"
    "-DSeastar_API_LEVEL=6"
    "-DSeastar_CXX_DIALECT=c++20"
    # "-DSeastar_UNUSED_RESULT_ERROR=ON"

    # Apps are needed by redpanda iotune
    "-DSeastar_APPS=ON"
  ];

  postInstall = ''
    for app in httpd io_tester io_tester iotune rpc_tester seawreck memcached
    do
      install apps/$app/$app $out/bin
    done
  '';

  doCheck = false;

  meta = with lib; {
    description = "High performance server-side application framework.";
    license = licenses.asl20;
    homepage = "https://seastar.io/";
    maintainers = with maintainers; [ avakhrenev ];
    platforms = platforms.unix;
  };
}
