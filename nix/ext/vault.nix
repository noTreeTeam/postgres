{ lib, stdenv, fetchFromGitHub, libsodium, postgresql }:

stdenv.mkDerivation rec {
  pname = "vault";
  version = "0.3.1";

  buildInputs = [ libsodium postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-kXTngBW4K6FkZM8HvJG2Jha6OQqbejhnk7tchxy031I=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    install -D *${postgresql.dlSuffix} $out/lib
    install -D -t $out/share/postgresql/extension sql/*.sql
    install -D -t $out/share/postgresql/extension *.control
  '';

  meta = with lib; {
    description = "Store encrypted secrets in PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
