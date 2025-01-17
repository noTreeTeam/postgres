{ lib
, stdenv
, fetchgit
, postgresql
, openssl
, curl
, pkg-config
, cacert
, rust-bin
, git
, python3
, darwin ? null
, lz4
, llvmPackages_16
, cmake
, readline
, patchelf
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
    rev = version;
    hash = if stdenv.isAarch64 && stdenv.isDarwin
      then "sha256-CUAbwirtrEbx97bGAU+/2wlB+nZ9fwb6ZuBptCJcxZ8="
      else "sha256-YJuahyx5N0fdxadCvtndfNoahnmU/kOWnXS0g/h+bWQ=";
    fetchSubmodules = true;
    leaveDotGit = true;
};

  configurePhase = "true";

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
    (lib.getDev postgresql)
  ] ++ lib.optionals (!stdenv.isDarwin) [
    patchelf
  ];

  buildInputs = [
    postgresql
    openssl
    curl
    cacert
    lz4.out
    readline
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.Security
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.CoreServices
    darwin.apple_sdk.frameworks.Foundation
    darwin.apple_sdk.frameworks.SystemConfiguration
    darwin.apple_sdk.frameworks.ApplicationServices
  ];

  makeFlags = [
    "PG_CONFIG=${postgresql}/bin/pg_config"
  ];

  patchPhase = ''
    # Handle the unused variables for both platforms
    sed -i 's/static constexpr char s3_filename_prefix/static constexpr __attribute__((unused)) char s3_filename_prefix/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char gcs_filename_prefix/static constexpr __attribute__((unused)) char gcs_filename_prefix/' src/pgduckdb/utility/copy.cpp
    sed -i 's/static constexpr char r2_filename_prefix/static constexpr __attribute__((unused)) char r2_filename_prefix/' src/pgduckdb/utility/copy.cpp  '' 
    + lib.optionalString (stdenv.isDarwin) ''
    # Rust build modifications for macOS
    sed -i '/cxx_build::bridge("src\/lib.rs")/c\    let mut build = cxx_build::bridge("src/lib.rs");\n    build.flag("-framework").flag("Security").flag("-framework").flag("CoreFoundation");' rust_extensions/delta/build.rs

    # Library suffix handling for macOS
    sed -i 's|libduckdb\.so|libduckdb.dylib|g' Makefile Makefile.build

    # Library lookup modifications
    find . -type f \( -name "Makefile" -o -name "Makefile.build" -o -name "*.cmake" -o -name "CMakeLists.txt" -o -name "*.make" \) -print0 | xargs -0 sed -i 's|-L[^ ]*/third_party/duckdb/build/release/src|-L../../third_party/duckdb/build/release/src -install_name @rpath/libduckdb.dylib|g'

    # Additional macOS configurations
    substituteInPlace third_party/duckdb/CMakeLists.txt --replace "-lz4" "-llz4"
    echo 'SO_MAJOR_VERSION=1' >> Makefile.build

    # Add macOS symbol exports for Rust
    # Ensure Rust functions are properly exported
cat > rust_extensions/delta/src/lib_export.rs << 'EOF'
    use std::os::raw::c_char;
    use std::ffi::CStr;
    use cxx::{CxxString, CxxVector};

    #[no_mangle]
    pub extern "C" fn delta_init() -> bool {
        super::DeltaInit();
        true
    }

    #[no_mangle]
    pub extern "C" fn DeltaCreateTable(
        table_name: *const c_char,
        path: *const c_char,
        options: *const c_char,
        column_names: *const *const c_char,
        column_types: *const *const c_char,
        column_count: i32
    ) -> bool {
        let result = std::panic::catch_unwind(|| {
            // Safe conversion of C strings to CxxString
            let table_name = unsafe { 
                CStr::from_ptr(table_name)
                    .to_str()
                    .map(|s| CxxString::new(s))
                    .unwrap_or_else(|_| CxxString::new(""))
            };
            
            let path = unsafe { 
                CStr::from_ptr(path)
                    .to_str()
                    .map(|s| CxxString::new(s))
                    .unwrap_or_else(|_| CxxString::new(""))
            };
            
            let options = unsafe { 
                CStr::from_ptr(options)
                    .to_str()
                    .map(|s| CxxString::new(s))
                    .unwrap_or_else(|_| CxxString::new(""))
            };
            
            // Convert column arrays to CxxVector<CxxString>
            let mut names = CxxVector::new();
            let mut types = CxxVector::new();
            
            for i in 0..column_count as isize {
                unsafe {
                    if let Ok(name) = CStr::from_ptr(*column_names.offset(i)).to_str() {
                        names.push(CxxString::new(name));
                    }
                    if let Ok(typ) = CStr::from_ptr(*column_types.offset(i)).to_str() {
                        types.push(CxxString::new(typ));
                    }
                }
            }
            
            match super::DeltaCreateTable(&table_name, &path, &options, &names, &types) {
                Ok(_) => true,
                Err(_) => false
            }
        });
        
        result.unwrap_or(false)
    }
    EOF
   
        # Add mod declaration to lib.rs
        echo "mod lib_export;" >> rust_extensions/delta/src/lib.rs 
  '';

  buildPhase = ''
    make -C third_party/duckdb release
    echo "=== Checking DuckDB Library Location ==="
    find third_party/duckdb -name "libduckdb*"
    ls -l third_party/duckdb
    echo "=== End DuckDB Library Check ==="
  
    # Setup build environment
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export HOME=$PWD/home
    export CARGO_HOME=$HOME/cargo
    export CC="${llvmPackages_16.clang}/bin/clang"
    export CXX="${llvmPackages_16.clang}/bin/clang++"
    mkdir -p "$CARGO_HOME"
        
    # Build Rust components first
    export CMAKE_FLAGS="-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
      -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
      -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON \
      -DENABLE_SANITIZER=FALSE \
      -DENABLE_UBSAN=0 \
      -DBUILD_SHELL=0 \
      -DBUILD_UNITTESTS=0 \
      -DCMAKE_BUILD_TYPE=Release"

    cargo build --release --manifest-path=rust_extensions/delta/Cargo.toml 
  
    # Create directories and copy libraries for linking
    mkdir -p $out/build/release
    cp rust_extensions/delta/target/release/libdelta.a $out/build/release/
    cp third_party/duckdb/build/release/src/libduckdb* $out/build/release/

    ${lib.optionalString (stdenv.isDarwin) ''
        # Darwin build command
        make USE_PGXS=1 V=1 VERBOSE=1 \
          BUILD_TYPE=release \
          CMAKE_FLAGS="$CMAKE_FLAGS" \
          PG_CONFIG=${postgresql}/bin/pg_config \
          DLSUFFIX=".dylib" \
          SHLIB_LINK="-L$out/build/release -L${postgresql}/lib -Wl,-undefined,dynamic_lookup -Wl,-rpath,@loader_path -llz4 -lduckdb -ldelta -lstdc++ $(${lib.getDev postgresql}/bin/pg_config --libs)" \
          PG_LIBS="$PG_LDFLAGS $FRAMEWORK_FLAGS" \
          all
      ''}
    ${lib.optionalString (!stdenv.isDarwin) ''
      make USE_PGXS=1 V=1 VERBOSE=1 \
        BUILD_TYPE=release \
        CMAKE_FLAGS="$CMAKE_FLAGS" \
        -j$NIX_BUILD_CORES all
    ''}
  '';

installPhase = ''
  mkdir -p $out/lib
  mkdir -p $out/share/postgresql/extension

  # Copy all the libraries to PostgreSQL's lib directory
  cp $out/build/release/libdelta.a $out/lib/
  cp $out/build/release/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
  cp build/release/${pname}${stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/

  # Platform-specific library path fixing
  ${if stdenv.isDarwin then ''
    # Fix ID of libduckdb
    install_name_tool -id "@loader_path/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}" \
      $out/lib/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}

    # Fix references in pg_mooncake
    install_name_tool -change "@rpath/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}" \
      "@loader_path/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}" \
      $out/lib/${pname}${stdenv.hostPlatform.extensions.sharedLibrary}
    install_name_tool -change "@loader_path/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}" \
      "@loader_path/libduckdb${stdenv.hostPlatform.extensions.sharedLibrary}" \
      $out/lib/${pname}${stdenv.hostPlatform.extensions.sharedLibrary}
  '' else ''
    patchelf --set-rpath '$ORIGIN' $out/lib/${pname}${stdenv.hostPlatform.extensions.sharedLibrary}
  ''}

  # Copy extension files
  cp ${pname}.control $out/share/postgresql/extension/
  cp sql/${pname}--*.sql $out/share/postgresql/extension/
'';
  meta = with lib; {
    description = "Mooncake: user-defined pipeline analytics in Postgres";
    homepage = "https://github.com/Mooncake-Labs/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
