{
  lib,
  stdenv,
  fetchgit,
  postgresql,
  cmake,
  openssl,
  curl,
  pkg-config,
  cacert,
  rust-bin,
  git,
  python3,
  darwin ? null
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

  src = fetchgit {
    url = "https://github.com/olirice/pg_mooncake.git";
    rev   = version;
    hash  = "sha256-CUAbwirtrEbx97bGAU+/2wlB+nZ9fwb6ZuBptCJcxZ8=";
    fetchSubmodules = true;
    leaveDotGit = true;
  };

  # Tools needed for building:
  nativeBuildInputs = [
    cargo
    rustc
    cmake
    pkg-config
    git
    python3
  ];

  buildInputs = [
    postgresql
    openssl
    curl
    cacert
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.Security
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.CoreServices
    darwin.apple_sdk.frameworks.Foundation
    darwin.apple_sdk.frameworks.SystemConfiguration
    darwin.apple_sdk.frameworks.ApplicationServices
  ];


  # Skip the default configure phase because there's no top-level CMakeLists.txt.
  dontConfigure = true;
 
  patchPhase = lib.optionalString (stdenv.isDarwin) ''
    # Replace libduckdb.so with libduckdb.dylib in Makefile and Makefile.build
    sed -i 's|libduckdb\.so|libduckdb.dylib|g' Makefile Makefile.build
    
    # Modify library lookup 
    find . -type f \( -name "Makefile" -o -name "Makefile.build" -o -name "*.cmake" -o -name "CMakeLists.txt" -o -name "*.make" \) -print0 | xargs -0 sed -i 's|-L[^ ]*/third_party/duckdb/build/release/src|-L../../third_party/duckdb/build/release/src -install_name @rpath/libduckdb.dylib|g'
  '' + ''
    # Modify copy.cpp to add __attribute__((unused)) to const variables
    sed -i 's/static constexpr char s3_filename_prefix\[\] = "s3:\/\/";/static constexpr char s3_filename_prefix[] __attribute__((unused)) = "s3:\/\/";/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char gcs_filename_prefix\[\] = "gs:\/\/";/static constexpr char gcs_filename_prefix[] __attribute__((unused)) = "gs:\/\/";/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char r2_filename_prefix\[\] = "r2:\/\/";/static constexpr char r2_filename_prefix[] __attribute__((unused)) = "r2:\/\/";/' src/pgduckdb/utility/copy.cpp
  '';

buildPhase = ''
  export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
  export HOME=$PWD/home
  export CARGO_HOME=$HOME/cargo
  mkdir -p "$CARGO_HOME"

  # Modify the Makefile to remove -Werror
  sed -i 's/-Werror//' Makefile

  # Add compiler flags to ignore unused const variables
  export CXXFLAGS="-Wno-error=unused-const-variable -Wno-unused-const-variable $CXXFLAGS"
  export CFLAGS="-Wno-error=unused-const-variable -Wno-unused-const-variable $CFLAGS"
  ${lib.optionalString (stdenv.isDarwin) ''
    # Export flags for both the linker and Rust
    export PG_LDFLAGS="-framework Security -framework CoreFoundation"
    export LDFLAGS="-framework Security -framework CoreFoundation -F${darwin.apple_sdk.frameworks.Security}/Library/Frameworks -F${darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks"
    export RUSTFLAGS="-C link-arg=-framework -C link-arg=Security -C link-arg=-framework -C link-arg=CoreFoundation"
    
    # Modify the PGXS Makefile to include our frameworks
    sed -i 's|^SHLIB_LINK =.*|& $(PG_LDFLAGS)|' $(pg_config --pgxs)
  ''}

  # Build the extension
  HOME="$HOME" \
  CARGO_HOME="$CARGO_HOME" \
  ${lib.optionalString (stdenv.isDarwin) ''
    make release SHARED_LIBRARY_NAME=libduckdb.dylib SHARED_LIBRARY_SUFFIX=.dylib \
      PG_LDFLAGS="$PG_LDFLAGS"
  ''} \
  ${lib.optionalString (!stdenv.isDarwin) ''
    make release
  ''} \
  -j$NIX_BUILD_CORES PG_CONFIG="${postgresql}/bin/pg_config" 
'';

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}
    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension

    # On Darwin, ensure library paths are correct
    ${lib.optionalString (stdenv.isDarwin) ''
      install_name_tool -change libduckdb.dylib @rpath/libduckdb.dylib $out/lib/*${postgresql.dlSuffix}
    ''}
  '';

  meta = with lib; {
    description = "Mooncake: user-defined pipeline analytics in Postgres";
    homepage    = "https://github.com/Mooncake-Labs/${pname}";
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
  };
}
