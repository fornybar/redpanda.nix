{ lib, stdenv, fetchzip }:

let
  arch = if stdenv.isAarch64 then "arm" else "amd";
  sha256s = {
    amd = "sha256-V96Ro1MFkTXb6WPY3/61W8Ksdb72TX/Fcfs9s+cKs4k=";
    arm = ""; # TODO: Figure out this
  };

in
stdenv.mkDerivation rec {
  pname = "redpandabin";
  version = "23.1.2";

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
  };

}

