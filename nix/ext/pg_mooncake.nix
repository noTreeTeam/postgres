{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  cmake,
  openssl,
  curl,
  pkg-config,
  cacert,
  rust-bin,
}:

let
  rustVersion = "1.81.0";
  targets = [
    "aarch64-apple-darwin"
    "x86_64-apple-darwin"
    "x86_64-unknown-linux-gnu"
    "aarch64-unknown-linux-gnu"
  ];
  rustc = rust-bin.stable."${rustVersion}".default.override {
    inherit targets;
  };
  cargo = rust-bin.stable."${rustVersion}".default.override {
    inherit targets;
  };
in
stdenv.mkDerivation rec {
  pname = "pg_mooncake";
  version = "61a2c495ba8e8bbcf59142f05dc85a3059bdf42c";

  src = fetchFromGitHub {
    owner = "olirice";
    repo  = pname;
    rev   = version;
    hash  = "sha256-zyQ0LREOSIF+25NODoZb8fTVH0sYEVu5YUqsJigWEb8=";
    fetchSubmodules = true;
  };

  # Tools needed for building:
  nativeBuildInputs = [
    cargo
    rustc
    cmake
    pkg-config
  ];

  buildInputs = [
    postgresql
    openssl
    curl
    cacert
  ];

  # Skip the default configure phase because there's no top-level CMakeLists.txt.
  dontConfigure = true;

  # Use "make release -j" with Nix's parallel build cores:
  buildPhase = ''
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

    # Make sure these env vars are set in the same shell invocation:
    export HOME=$PWD/home
    export CARGO_HOME=$HOME/cargo
    mkdir -p "$CARGO_HOME"

    # Pass HOME and CARGO_HOME explicitly to `make`, in case the upstream
    # Makefile does something like `HOME ?= /homeless-shelter`.
    HOME="$HOME" \
    CARGO_HOME="$CARGO_HOME" \
      make release -j$NIX_BUILD_CORES PG_CONFIG="${postgresql}/bin/pg_config"
  '';

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Mooncake: user-defined pipeline analytics in Postgres";
    homepage    = "https://github.com/Mooncake-Labs/${pname}";
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
  };
}
