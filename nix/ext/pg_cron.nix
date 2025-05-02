{ 
  lib, 
  stdenv, 
  fetchFromGitHub, 
  postgresql,
  runCommand
}:

let
  pname = "pg_cron";

  meta = with lib; {
    description = "Run Cron jobs through PostgreSQL (multi-version compatible)";
    homepage = "https://github.com/citusdata/${pname}";
    inherit (postgresql.meta) platforms;
    license = licenses.postgresql;
  };

  allVersions = {
    "1.6.4" = "sha256-t1DpFkPiSfdoGG2NgNT7g1lkvSooZoRoUrix6cBID40=";
    "1.5.2" = "sha256-+quVWbKJy6wXpL/zwTk5FF7sYwHA7I97WhWmPO/HSZ4=";
    "1.4.2" = "sha256-P0Fd10Q1p+KrExb35G6otHpc6pD61WnMll45H2jkevM=";
  };

  getVersions = pg:
    if lib.versionAtLeast pg.version "17"
    then { "1.6.4" = allVersions."1.6.4"; }
    else allVersions;

  mkPackage = version: hash:
    stdenv.mkDerivation (finalAttrs: {
      inherit pname meta;
      version = "${version}-pg${lib.versions.major postgresql.version}";

      src = fetchFromGitHub {
        owner = "citusdata";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      buildInputs = [ postgresql ];

      buildPhase = ''
        make PG_CONFIG=${postgresql}/bin/pg_config
  
        # Create version-specific SQL file
        cp pg_cron.sql pg_cron--${version}.sql

        # Create versioned control file with modified module path
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/pg_cron'|" \
            pg_cron.control > pg_cron--${version}.control
      '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}
        
        # Install versioned library
        install -Dm755 pg_cron${postgresql.dlSuffix} $out/lib/pg_cron-${version}${postgresql.dlSuffix}
        
        # Install version-specific files
        install -Dm644 pg_cron--${version}.sql $out/share/postgresql/extension/
        install -Dm644 pg_cron--${version}.control $out/share/postgresql/extension/
        
        # Install upgrade scripts
        find . -name 'pg_cron--*--*.sql' -exec install -Dm644 {} $out/share/postgresql/extension/ \;
      '';
    });

  packages = lib.listToAttrs (
    lib.attrValues (
      lib.mapAttrs (version: hash: lib.nameValuePair "v${version}" (mkPackage version hash)) (getVersions postgresql)
    )
  );

in
runCommand "${pname}-all"
  {
    inherit pname meta;
    version = "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings ["."] ["-"] v) (lib.attrNames (getVersions postgresql)));

    buildInputs = lib.attrValues packages;

    passthru = {
      inherit packages;
    };
  }
  ''
    mkdir -p $out/{lib,share/postgresql/extension,bin}
    
    # Install all versions
    for drv in ''${buildInputs[@]}; do
      ln -sv $drv/lib/* $out/lib/
      cp -v --no-clobber $drv/share/postgresql/extension/* $out/share/postgresql/extension/ || true
    done
    
    # Create default symlinks
    latest_control=$(ls -v $out/share/postgresql/extension/pg_cron--*.control | tail -n1)
    latest_version=$(basename "$latest_control" | sed -E 's/pg_cron--([0-9.]+).control/\1/')
    
    # Create main control file with default_version
    echo "default_version = '$latest_version'" > $out/share/postgresql/extension/pg_cron.control
    cat "$latest_control" >> $out/share/postgresql/extension/pg_cron.control
    
    # Library symlink
    ln -sfnv pg_cron-$latest_version${postgresql.dlSuffix} $out/lib/pg_cron${postgresql.dlSuffix}

    # Create version switcher script
    cat > $out/bin/switch_pg_cron_version <<'EOF'
    #!/bin/sh
    set -e

    if [ $# -ne 1 ]; then
      echo "Usage: $0 <version>"
      echo "Example: $0 1.4.2"
      exit 1
    fi

    VERSION=$1
    LIB_DIR=$(dirname "$0")/../lib

    # Use platform-specific extension
    if [ "$(uname)" = "Darwin" ]; then
      EXT=".dylib"
    else
      EXT=".so"
    fi

    # Check if version exists
    if [ ! -f "$LIB_DIR/pg_cron-$VERSION$EXT" ]; then
      echo "Error: Version $VERSION not found"
      exit 1
    fi

    # Update library symlink
    ln -sfnv "pg_cron-$VERSION$EXT" "$LIB_DIR/pg_cron$EXT"

    echo "Successfully switched pg_cron to version $VERSION"
    EOF

    chmod +x $out/bin/switch_pg_cron_version
  ''
