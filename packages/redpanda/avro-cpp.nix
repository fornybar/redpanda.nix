{ stdenv, fetchFromGitHub, cmake, boost, python3 }:

stdenv.mkDerivation {
  pname = "avro-c++";
  version = "redpanda";

  cmakeDir = "../redpanda_build";

  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "avro";
    rev = "d9f4cee17241f70554c6bcd0ba914a90b67b05cc"; # release-1.11.1-redpanda branch
    hash = "sha256-a9rwzfRnV7zxSdd/toRddrqKs70JjFNsIIZ6U7aqKJg=";
  };

  nativeBuildInputs = [ cmake python3 ];
  buildInputs = [ boost ];
}


