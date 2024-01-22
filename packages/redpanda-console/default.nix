{ lib, stdenv, fetchzip }:
stdenv.mkDerivation rec {
  pname = "redpanda-console";
  version = "2.3.9";

  src = fetchzip {
    url = "https://github.com/redpanda-data/console/releases/download/v${version}/redpanda_console_${version}_linux_amd64.tar.gz";
    sha256 = "sha256-pTlghp2cCXmWZBOAUHiV0iG4btdhssp3QzvzuS+/ENo=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp redpanda-console $out/bin
    runHook postInstall
  '';

  meta = with lib; {
    # TODO: Fill out meta
    platforms = platforms.linux;
    disabled = stdenv.isAarch64; # TODO: Enable for other architectures
  };
}
