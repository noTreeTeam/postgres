{ lib, stdenv, fetchFromGitHub, postgresql }:

let
  allVersions = {
    "1.6.4" = {
      rev = "v1.6.4";
      hash = "sha256-t1DpFkPiSfdoGG2NgNT7g1lkvSooZoRoUrix6cBID40=";
    };
    "1.5.2" = {
      rev = "v1.5.2";
      hash = "sha256-+quVWbKJy6wXpL/zwTk5FF7sYwHA7I97WhWmPO/HSZ4=";
    };
  };

  mkPgCron = pgCronVersion: { rev, hash }: stdenv.mkDerivation {
    pname = "pg_cron";
    version = "${pgCronVersion}-pg${lib.versions.major postgresql.version}";

    buildInputs = [ postgresql ];

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
      mkdir -p $out/{lib,share/postgresql/extension}
      
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
  version = "multi";

  buildInputs = lib.attrValues allVersionsForPg;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}
    
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
  '';

  meta = with lib; {
    description = "Run Cron jobs through PostgreSQL (multi-version compatible)";
    homepage = "https://github.com/citusdata/pg_cron";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
