# Use nixpkgs TimescaleDB if available, otherwise fallback to building from source
{ lib, stdenv, fetchFromGitHub, cmake, postgresql, openssl, libkrb5 }:

# Try to use the prebuilt TimescaleDB from nixpkgs first
# This provides TimescaleDB 2.19.3+ and avoids build times
if postgresql.pkgs ? timescaledb-apache then
  postgresql.pkgs.timescaledb-apache
else 
  # Fallback to building from source (TimescaleDB 2.17.0)
  stdenv.mkDerivation rec {
    pname = "timescaledb-apache";
    version = "2.17.0";

    nativeBuildInputs = [ cmake ];
    buildInputs = [ postgresql openssl libkrb5 ];

    src = fetchFromGitHub {
      owner = "timescale";
      repo = "timescaledb";
      rev = version;
      hash = "sha256-6e/PdHpCXn5Dxdip8ICG+vXxezDATQkwHqDqkt7SS48=";
    };

  cmakeFlags = [ "-DSEND_TELEMETRY_DEFAULT=OFF" "-DREGRESS_CHECKS=OFF" "-DTAP_CHECKS=OFF" "-DAPACHE_ONLY=1" ]
    ++ lib.optionals stdenv.isDarwin [ "-DLINTER=OFF" ];

  # Fix the install phase which tries to install into the pgsql extension dir,
  # and cannot be manually overridden. This is rather fragile but works OK.
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
    description = "Scales PostgreSQL for time-series data via automatic partitioning across time and space";
    homepage = "https://www.timescale.com/";
    changelog = "https://github.com/timescale/timescaledb/blob/${version}/CHANGELOG.md";
    platforms = postgresql.meta.platforms;
    license = licenses.asl20;
    broken = versionOlder postgresql.version "13";
  };
}
