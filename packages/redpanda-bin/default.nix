{ lib, stdenv, fetchzip }:

let
  arch = if stdenv.isAarch64 then "arm" else "amd";
  sha256s = {
    amd = "sha256-AOaG7utDWkV+CMt6c0iMgcRFbqCW+RQI4K+E85V771w=";
    arm = ""; # TODO: Figure out this
  };

in
stdenv.mkDerivation rec {
  pname = "redpanda-bin";
  version = "23.3.1";

  src = fetchzip {
    url = "https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/raw/names/redpanda-${arch}64/versions/${version}/redpanda-${version}-${arch}64.tar.gz";
    sha256 = sha256s.${arch};
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall

    cp -R  $src $out

    runHook postInstall
  '';

  preFixup = ''
    substituteInPlace $out/bin\/* \
      --replace '/opt/redpanda' $out

    for file in $(find $out/libexec -type f ! -name rpk); do
      patchelf --set-interpreter $out/lib/ld.so $file
    done
  '';

  meta = with lib; {
    # TODO: Fill out meta
    platforms = platforms.linux;
    # XXX: should probably be "rpk" but that would be surprising for users
    mainProgram = "redpanda";
  };

}

