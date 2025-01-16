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
  darwin ? null,
  lz4,
  llvmPackages_16
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
    lz4.dev
    llvmPackages_16.clang
    llvmPackages_16.libllvm
  ];

  buildInputs = [
    postgresql
    openssl
    curl
    cacert
    lz4.out
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
    sed -i '/cxx_build::bridge("src\/lib.rs")/c\    let mut build = cxx_build::bridge("src/lib.rs");\n    build.flag("-framework").flag("Security").flag("-framework").flag("CoreFoundation");' rust_extensions/delta/build.rs
    # Replace libduckdb.so with libduckdb.dylib in Makefile and Makefile.build
    sed -i 's|libduckdb\.so|libduckdb.dylib|g' Makefile Makefile.build
    
    # Modify library lookup 
    find . -type f \( -name "Makefile" -o -name "Makefile.build" -o -name "*.cmake" -o -name "CMakeLists.txt" -o -name "*.make" \) -print0 | xargs -0 sed -i 's|-L[^ ]*/third_party/duckdb/build/release/src|-L../../third_party/duckdb/build/release/src -install_name @rpath/libduckdb.dylib|g'
    substituteInPlace third_party/duckdb/CMakeLists.txt --replace "-lz4" "-llz4"
    echo 'SO_MAJOR_VERSION=1' >> Makefile.build
    # Add a new file to export symbols on macOS
    cat > rust_extensions/delta/src/lib_export.rs << 'EOF'
    use std::ffi::CString;
    use std::os::raw::c_char;
    use cxx::{CxxString, CxxVector};

    // Directly re-export the original functions to ensure symbol availability
    #[no_mangle]
    pub extern "C" fn delta_init() -> bool {
        match super::DeltaInit() {
            Ok(_) => true,
            Err(_) => {
                eprintln!("Delta initialization failed");
                false
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn delta_create_table(
        table_name: *const c_char,
        path: *const c_char,
        options: *const c_char,
        column_names: *const *const c_char,
        column_types: *const *const c_char,
        column_count: libc::c_int
    ) -> bool {
        // TODO: Implement proper conversion from C types to CxxString and CxxVector
        false // Placeholder
    }

    #[no_mangle]
    pub extern "C" fn delta_modify_files(
        path: *const c_char,
        options: *const c_char,
        file_paths: *const *const c_char,
        file_sizes: *const i64,
        is_add_files: *const i8,
        file_count: libc::c_int
    ) -> bool {
        // TODO: Implement proper conversion from C types to CxxString and CxxVector
        false // Placeholder
    }
          EOF
          
    # Add mod declaration to lib.rs
    echo "mod lib_export;" >> rust_extensions/delta/src/lib.rs 
    sed -i 's/-Werror//' Makefile 
  '' + ''
    # Modify copy.cpp to add __attribute__((unused)) to const variables
    sed -i 's/static constexpr char s3_filename_prefix\[\]/static constexpr [[maybe_unused]] char s3_filename_prefix[]/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char gcs_filename_prefix\[\]/static constexpr [[maybe_unused]] char gcs_filename_prefix[]/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char r2_filename_prefix\[\]/static constexpr [[maybe_unused]] char r2_filename_prefix[]/' src/pgduckdb/utility/copy.cpp
  '';

  buildPhase = ''
    set -x  
    
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export HOME=$PWD/home
    export CARGO_HOME=$HOME/cargo
    export CC="${llvmPackages_16.clang}/bin/clang"
    export CXX="${llvmPackages_16.clang}/bin/clang++"
    mkdir -p "$CARGO_HOME"
    
    echo "=== Checking Cargo Build ==="
    cargo build --release --manifest-path=rust_extensions/delta/Cargo.toml -vv
    echo "=== End Cargo Build ==="
    echo "=== List  ==="
    ls -la rust_extensions/delta/target/release/
    echo "=== End List ==="
    sed -i 's/-Werror//' Makefile
    
    ${lib.optionalString (stdenv.isDarwin) ''
      export CXXFLAGS="-Wno-error=unused-const-variable -Wno-unused-const-variable $CXXFLAGS"
      export DLSUFFIX=".dylib"
    ''}
    ${lib.optionalString (!stdenv.isDarwin) ''
      export CXXFLAGS="-Wno-error=unused-const-variable -Wno-unused-const-variable $CXXFLAGS"
    ''}
    export CFLAGS="-Wno-error=unused-const-variable -Wno-unused-const-variable $CFLAGS"
    
    ${lib.optionalString (stdenv.isDarwin) ''
      # Bundle loader and C++ runtime flags
      export PG_LDFLAGS="-bundle -bundle_loader ${postgresql}/bin/postgres -lc++ -lc++abi"
      # Framework flags
      export FRAMEWORK_FLAGS="-F${darwin.apple_sdk.frameworks.Security}/Library/Frameworks -F${darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks"
    ''}

    HOME="$HOME" \
    CARGO_HOME="$CARGO_HOME" \
    ${lib.optionalString (stdenv.isDarwin) ''
      # First part of make to get Makefile.build copied
      make BUILD_TYPE=release all
      sed -i 's/\$(CXX) \$(CXXFLAGS)/\$(CXX) \$(CXXFLAGS) -Wno-error=unused-const-variable -Wno-unused-const-variable/' build/release/Makefile

      # echo "=== Checking Delta Library ==="
      # file rust_extensions/delta/target/release/libdelta.a || echo "No libdelta.a in rust_extensions"
      # file build/release/libdelta.a || echo "No libdelta.a in build/release"
      # nm rust_extensions/delta/target/release/libdelta.a || echo "No Delta symbols found"
      # echo "=== End Delta Library Check ==="
      
      # Now patch the copied Makefile
      cp rust_extensions/delta/target/release/libdelta.a build/release/
      # The linker processes libraries in order from left to right. When it encounters an undefined symbol, it looks ahead to find a library defining that symbol
      # Once processed, a library isn't revisited even if later libraries need its symbols
      # in our case:
      # pgduckdb_detoast.cpp.o needs LZ4_decompress_safe from lz4
      # lake.cpp.o needs Delta* symbols from libdelta.a
      # libdelta.a needs symbols from lz4 and duckdb
      sed -i 's|SHLIB_LINK := -L. -Wl,-rpath,$(PG_LIB_DIR) -lduckdb -lstdc++|SHLIB_LINK := -llz4 -lduckdb ../../rust_extensions/delta/target/release/libdelta.a -lstdc++|' build/release/Makefile
      # Continue with the build
      make -C build/release V=1 VERBOSE=1 DLSUFFIX=".dylib" \
      SHARED_LIBRARY_NAME=libduckdb.dylib \
      SHARED_LIBRARY_SUFFIX=.dylib \
      PG_LIBS="$PG_LDFLAGS $FRAMEWORK_FLAGS"
    ''} \
    ${lib.optionalString (!stdenv.isDarwin) ''
      make release
    ''} \
    -j$NIX_BUILD_CORES PG_CONFIG="${postgresql}/bin/pg_config"
  '';

  meta = with lib; {
    description = "Mooncake: user-defined pipeline analytics in Postgres";
    homepage    = "https://github.com/Mooncake-Labs/${pname}";
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
  };
}