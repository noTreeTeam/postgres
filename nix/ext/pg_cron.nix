{ lib, stdenv, fetchFromGitHub, postgresql }:

let
  allVersions = {
    "1.3.1" = {
      rev = "v1.3.1";
      hash = "sha256-rXotNOtQNmA55ErNxGoNSKZ0pP1uxEVlDGITFHuqGG4=";
      patches = [ ./pg_cron-1.3.1-pg15.patch ];
    };
    "1.4.2" = {
      rev = "v1.4.2";
      hash = "sha256-P0Fd10Q1p+KrExb35G6otHpc6pD61WnMll45H2jkevM=";
    };
    "1.6.4" = {
      rev = "v1.6.4";
      hash = "sha256-t1DpFkPiSfdoGG2NgNT7g1lkvSooZoRoUrix6cBID40=";
    };
    "1.5.2" = {
      rev = "v1.5.2";
      hash = "sha256-+quVWbKJy6wXpL/zwTk5FF7sYwHA7I97WhWmPO/HSZ4=";
    };
  };

  # Simple version string that concatenates all versions with dashes
  versionString = "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings ["."] ["-"] v) (lib.attrNames allVersions));

  mkPgCron = pgCronVersion: { rev, hash, patches ? [] }: stdenv.mkDerivation {
    pname = "pg_cron";
    version = "${pgCronVersion}-pg${lib.versions.major postgresql.version}";

    buildInputs = [ postgresql ];
    inherit patches;

    src = fetchFromGitHub {
      owner = "citusdata";
      repo = "pg_cron";
      inherit rev hash;
    };

    buildPhase = ''
      make PG_CONFIG=${postgresql}/bin/pg_config
  
      # Create version-specific SQL file
      cp pg_cron.sql pg_cron--${pgCronVersion}.sql

      # Create versioned control file with modified module path
      sed -e "/^default_version =/d" \
          -e "s|^module_pathname = .*|module_pathname = '\$libdir/pg_cron'|" \
          pg_cron.control > pg_cron--${pgCronVersion}.control
    '';

    installPhase = ''
      mkdir -p $out/{lib,share/postgresql/extension,bin}
      
      # Install versioned library
      install -Dm755 pg_cron${postgresql.dlSuffix} $out/lib/pg_cron-${pgCronVersion}${postgresql.dlSuffix}
      
      # Install version-specific files
      install -Dm644 pg_cron--${pgCronVersion}.sql $out/share/postgresql/extension/
      install -Dm644 pg_cron--${pgCronVersion}.control $out/share/postgresql/extension/
      
      # Install upgrade scripts
      find . -name 'pg_cron--*--*.sql' -exec install -Dm644 {} $out/share/postgresql/extension/ \;
    '';
  };

  getVersions = pg:
    if lib.versionAtLeast pg.version "17"
    then { "1.6.4" = allVersions."1.6.4"; }
    else allVersions;

  allVersionsForPg = lib.mapAttrs mkPgCron (getVersions postgresql);

in
stdenv.mkDerivation {
  pname = "pg_cron-all";
  version = versionString;

  buildInputs = lib.attrValues allVersionsForPg;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension,bin}
    
    # Install all versions
    for drv in ${lib.concatStringsSep " " (lib.attrValues allVersionsForPg)}; do
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
    NIX_PROFILE="/var/lib/postgresql/.nix-profile"
    LIB_DIR="$out/lib"
    EXTENSION_DIR="$NIX_PROFILE/share/postgresql/extension"

    # Check if version exists
    if [ ! -f "$LIB_DIR/pg_cron-$VERSION${postgresql.dlSuffix}" ]; then
      echo "Error: Version $VERSION not found"
      exit 1
    fi

    # Update library symlink
    ln -sfnv "pg_cron-$VERSION${postgresql.dlSuffix}" "$LIB_DIR/pg_cron${postgresql.dlSuffix}"

    # Update control file
    echo "default_version = '$VERSION'" > "$EXTENSION_DIR/pg_cron.control"
    cat "$EXTENSION_DIR/pg_cron--$VERSION.control" >> "$EXTENSION_DIR/pg_cron.control"

    echo "Successfully switched pg_cron to version $VERSION"
    EOF

    chmod +x $out/bin/switch_pg_cron_version
  '';

  meta = with lib; {
    description = "Run Cron jobs through PostgreSQL (multi-version compatible)";
    homepage = "https://github.com/citusdata/pg_cron";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
