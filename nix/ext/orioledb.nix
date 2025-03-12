{ lib, stdenv, fetchFromGitHub, curl, libkrb5, postgresql, python3, openssl, enableDebugging ? false }:

stdenv.mkDerivation rec {
  pname = "orioledb";
  name = pname;
  src = fetchFromGitHub {
    owner = "orioledb";
    repo = "orioledb";
    rev = "beta7";
    sha256 = "sha256-Rse/gYVkn4QvXipaJ8fyC6FIQ5afkLCaeylgp5MX1z8=";
  };
  version = "beta7";
  buildInputs = [ curl libkrb5 postgresql python3 openssl ];
  
  # Add debug flags if enableDebugging is true
  buildPhase = if enableDebugging then
    "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=5 CFLAGS='-g3'"
  else
    "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=5";
  
  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
    
    # Also copy source files if debugging is enabled
    ${lib.optionalString enableDebugging ''
      mkdir -p $out/src
      cp -r . $out/src
    ''}
        
    runHook postInstall
  '';
  
  # Don't strip debug symbols if debugging is enabled
  dontStrip = enableDebugging;
  
  doCheck = true;
  meta = with lib; {
    description = "orioledb";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}