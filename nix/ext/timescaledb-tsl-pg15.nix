{ lib, stdenv, fetchFromGitHub, cmake, postgresql, openssl, libkrb5 }:

# TimescaleDB 2.17.0 with full TSL features for PostgreSQL 13-16.
# 2.20.3+ dropped PG15 support — use this derivation for PG15 builds.
stdenv.mkDerivation rec {
  pname = "timescaledb";
  version = "2.17.0";

  nativeBuildInputs = [ cmake ];
  buildInputs = [ postgresql openssl libkrb5 ];

  src = fetchFromGitHub {
    owner = "timescale";
    repo = "timescaledb";
    rev = version;
    hash = "sha256-6e/PdHpCXn5Dxdip8ICG+vXxezDATQkwHqDqkt7SS48=";
  };

  cmakeFlags = [ "-DSEND_TELEMETRY_DEFAULT=OFF" "-DREGRESS_CHECKS=OFF" "-DTAP_CHECKS=OFF" ]
    ++ lib.optionals stdenv.isDarwin [ "-DLINTER=OFF" ];

  postPatch = ''
    for x in CMakeLists.txt sql/CMakeLists.txt; do
      substituteInPlace "$x" \
        --replace 'DESTINATION "''${PG_SHAREDIR}/extension"' "DESTINATION \"$out/share/postgresql/extension\""
    done

    for x in src/CMakeLists.txt src/loader/CMakeLists.txt tsl/src/CMakeLists.txt; do
      substituteInPlace "$x" \
        --replace 'DESTINATION ''${PG_PKGLIBDIR}' "DESTINATION \"$out/lib\""
    done
  '';

  meta = with lib; {
    description = "Scales PostgreSQL for time-series data with full TSL features (PG15 compatible)";
    homepage = "https://www.timescale.com/";
    platforms = postgresql.meta.platforms;
    license = licenses.tsl;
    broken = versionOlder postgresql.version "13";
  };
}
