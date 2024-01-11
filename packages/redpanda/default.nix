{ lib
, fetchFromGitHub
, fetchgit
, newScope
  # dependencies
, abseil-cpp_202206
, avro-cpp
, boost175
, bzip2
, fmt_8
, gtest
, icu
, llvmPackages_16
, lzma
, protobuf_21
, python310
, re2
, yaml-cpp
, zlib
, zstd
, cryptopp
, liburing
}:

lib.makeScope newScope (self:
let inherit (self) callPackage; in
{
  redpanda_version = "23.3.1";
  # see redpanda/cmake/dependencies.cmake
  seastar_version = "23.3.x";

  redpanda_src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "redpanda";
    rev = "v${self.redpanda_version}";
    hash = "sha256-xYUL681Ek3eJw5SPdMjlIjt7T87d09+xfJNCcC9tTpE=";
  };

  redpanda-client = callPackage ./redpanda.nix { };

  redpanda-server = callPackage ./server.nix { };

  seastar = callPackage ./seastar.nix { };

  base64 = callPackage ./base64.nix { };

  hdr-histogram = callPackage ./hdr-histogram.nix { };

  rapidjson = callPackage ./rapidjson.nix { };

  # We have to build with clang 16 and libc++
  llvmPackages = llvmPackages_16;
  clangStdenv = self.llvmPackages.libcxxStdenv;
  stdenv = self.clangStdenv;

  # All the dependencies, and their dependencies, and... need to be built with
  # libc++ If the build fails due to missing symbols with templates, you have a
  # c++ lib mismatch between libc++ and libstdc++. You have to add that
  # dependency here, and override packages that use it (see protobuf and
  # avro-cpp for example).
  abseil-cpp = abseil-cpp_202206.override { inherit (self) stdenv; };
  cryptopp = cryptopp.override { inherit (self) stdenv; };
  fmt_8 = fmt_8.override { inherit (self) stdenv; };
  gtest = gtest.override { inherit (self) stdenv; };
  protobuf = protobuf_21.override { inherit (self) stdenv abseil-cpp gtest; };
  yaml-cpp = yaml-cpp.override { inherit (self) stdenv; };

  boost = boost175.override {
    inherit (self) stdenv;
    enablePython = true;
    # Build fails with python 3.11, should be fixed in more recent boost versions
    python = python310; # XXX I do not think it is needed: .withPackages (ps: [ ps.jinja2 ]);
  };

  avro-cpp = (avro-cpp.override {
    inherit (self) stdenv boost;
  }).overrideAttrs (oldAttrs: {
    # XXX: Why are these suddenly needed when built with clang and libc++ ?
    buildInputs = oldAttrs.buildInputs or [ ] ++ [ zlib icu bzip2 lzma zstd ];
  });


  liburing = (liburing.override {
    inherit (self) stdenv;
  }).overrideAttrs (oldAttrs: rec {
    # liburing needs to be <= 2.2,
    # see https://github.com/redpanda-data/seastar/pull/91
    pname = "liburing";
    version = "2.2";
    name = "${pname}-${version}";

    src = fetchgit {
      url = "http://git.kernel.dk/${pname}";
      rev = "liburing-${version}";
      sha256 = "sha256-M/jfxZ+5DmFvlAt8sbXrjBTPf2gLd9UyTNymtjD+55g=";
    };
  });

  re2 = (re2.override {
    inherit (self) stdenv;
  }).overrideAttrs (oldAttrs: rec {
    # re2 needs to be < 2023-06-01,
    # see https://github.com/redpanda-data/redpanda/issues/15408
    pname = "re2";
    version = "2023-03-01";
    name = "${pname}-${version}";
    src = fetchFromGitHub {
      owner = "google";
      repo = "re2";
      rev = version;
      hash = "sha256-T+P7qT8x5dXkLZAL8VjvqPD345sa6ALX1f5rflE0dwc=";
    };
  });

})
