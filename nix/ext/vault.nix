{ pkgs, lib, stdenv, fetchFromGitHub, libsodium, postgresql }:
let
  pname = "supabase_vault";

  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};

  # Filter versions compatible with current PostgreSQL version
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;

  # Derived version information
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );

  # Build function for individual pgsodium versions
  build =
    version: hash:

    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ libsodium postgresql ];

      src = fetchFromGitHub {
        owner = "supabase";
        repo = "vault";
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}


        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

      '' + lib.optionalString (builtins.compareVersions "0.2.8" version < 0) ''
        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # For the latest version, copy the sql files
        if [[ "${version}" == "${latestVersion}" ]]; then
          install -D -t $out/share/postgresql/extension sql/*.sql
            {
              echo "default_version = '${latestVersion}'"
              cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
            } > $out/share/postgresql/extension/${pname}.control
        fi
        ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
      '';

      meta = with lib; {
        description = "Store encrypted secrets in PostgreSQL";
        homepage = "https://github.com/supabase/${pname}";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
in
pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
