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
, seastar_ref
, valgrind
, yaml-cpp
}:

llvmPackages.libcxxStdenv.mkDerivation {
  pname = "seastar";
  version = seastar_version;
  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "seastar";
    rev = seastar_ref;
    sha256 = "sha256-nGDw9FwasVfHc1RuBH29SR17x5uNS0CbBsDwOdUvH0s=";
  };

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
    "-DSeastar_APPS=OFF"
    "-DSeastar_DEMOS=OFF"
    "-DSeastar_DOCS=OFF"
    "-DSeastar_TESTING=OFF"
    "-DSeastar_API_LEVEL=6"
    "-DSeastar_CXX_DIALECT=c++20"
    # "-DSeastar_UNUSED_RESULT_ERROR=ON"
  ];

  doCheck = false;

  meta = with lib; {
    description = "High performance server-side application framework.";
    license = licenses.asl20;
    homepage = "https://seastar.io/";
    maintainers = with maintainers; [ avakhrenev ];
    platforms = platforms.unix;
  };
}
