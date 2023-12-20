{ buildGoModule
, doCheck ? !stdenv.isDarwin # Can't start localhost test server in MacOS sandbox.
, installShellFiles
, lib
, stdenv
, redpanda_src
, redpanda_version
, hwloc
, seastar
, redpanda-server
}:

buildGoModule rec {
  pname = "redpanda-client";
  inherit doCheck;
  src = redpanda_src;
  version = redpanda_version;
  modRoot = "./src/go/rpk";
  runVend = false;
  vendorHash = "sha256-mLMMw48d1FOvIIjDNza0rZSWP55lP1AItR/hT3lYXDg=";

  ldflags = [
    ''-X "github.com/redpanda-data/redpanda/src/go/rpk/pkg/cli/cmd/version.version=${version}"''
    ''-X "github.com/redpanda-data/redpanda/src/go/rpk/pkg/cli/cmd/version.rev=v${version}"''
    ''-X "github.com/redpanda-data/redpanda/src/go/rpk/pkg/cli/cmd/container/common.tag=v${version}"''
  ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    for shell in bash fish zsh; do
      $out/bin/rpk generate shell-completion $shell > rpk.$shell
      installShellCompletion rpk.$shell
    done

    # Copy instead of symlink to reduce closure size.
    # These are self-contained binaries anyway.
    mkdir -p $out/libexec $out/bin
    install -m 755 ${hwloc}/bin/hwloc-calc $out/libexec/hwloc-calc-redpanda
    install -m 755 ${hwloc}/bin/hwloc-distrib $out/libexec/hwloc-distrib-redpanda
    install -m 755 ${seastar}/bin/iotune $out/libexec/iotune-redpanda
    install -m 755 ${redpanda-server}/bin/rp_util $out/libexec/rp_util

    # The official release archive also has these binaries in //bin
    ln -sn $out/libexec/* $out/bin
  '';

  meta = with lib; {
    description = "Redpanda client";
    homepage = "https://redpanda.com/";
    license = licenses.bsl11;
    maintainers = with maintainers; [ avakhrenev happysalada ];
    platforms = platforms.all;
    mainProgram = "rpk";
  };
}
