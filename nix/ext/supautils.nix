{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.7.3";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-QKQQUz6ObzqINTLZaMQtocOkYX0Rh61fBLoB+rZ64UM=";
  };

  installPhase = ''
    mkdir -p $out/lib

    install -D build/*${postgresql.dlSuffix} -t $out/lib
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ steve-chavez ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
