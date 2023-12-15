{ buildGoModule
, doCheck ? !stdenv.isDarwin # Can't start localhost test server in MacOS sandbox.
, installShellFiles
, lib
, stdenv
, redpanda_src
, redpanda_version
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
