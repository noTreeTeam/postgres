{ self, ... }:
{
  imports = [
    ./postgres.nix
  ];
  perSystem =
    {
      inputs',
      config,
      lib,
      pkgs,
      self',
      ...
    }:
    let
      activeVersion = "15";
      # Function to create the pg_regress package
      makePgRegress =
        version:
        let
          postgresqlPackage = self'.packages."postgresql_${version}";
        in
        pkgs.callPackage ../ext/pg_regress.nix {
          postgresql = postgresqlPackage;
        };
      pgsqlDefaultPort = "5435";
      pgsqlSuperuser = "supabase_admin";
    in
    {
      packages = (
        {
          build-test-ami = pkgs.callPackage ./build-test-ami.nix { };
          cleanup-ami = pkgs.callPackage ./cleanup-ami.nix { };
          dbmate-tool = pkgs.callPackage ./dbmate-tool.nix { };
          supabase-groonga = pkgs.callPackage ../supabase-groonga.nix { };
          local-infra-bootstrap = pkgs.callPackage ./local-infra-bootstrap.nix { };
          migrate-tool = pkgs.callPackage ./migrate-tool.nix { inherit (self'.packages) psql_15; };
          pg-restore = pkgs.callPackage ./pg-restore.nix { inherit (self'.packages) psql_15; };
          pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
          pg_regress = makePgRegress activeVersion;
          postgresql_15_src = pkgs.callPackage ./postgresql-src.nix {
            postgresql = self'.packages.postgresql_15;
          };
          postgresql_17_src = pkgs.callPackage ./postgresql-src.nix {
            postgresql = self'.packages.postgresql_17;
          };
          postgresql_orioledb-17_src = pkgs.callPackage ./postgresql-src.nix {
            postgresql = self'.packages.postgresql_orioledb-17;
          };
          run-testinfra = pkgs.callPackage ./run-testinfra.nix { };
          show-commands = pkgs.callPackage ./show-commands.nix { };
          start-client = pkgs.callPackage ./start-client.nix {
            inherit (self'.packages) psql_15 psql_17 psql_orioledb-17;
            inherit pgsqlSuperuser pgsqlDefaultPort;
          };
          start-replica = pkgs.callPackage ./start-replica.nix {
            inherit (self'.packages) psql_15;
            inherit pgsqlSuperuser;
          };
          start-server = pkgs.callPackage ./start-server.nix {
            inherit (self'.packages) psql_15 psql_17 psql_orioledb-17;
            inherit pgsqlSuperuser pgsqlDefaultPort;
          };
          inherit (pkgs.callPackage ../wal-g.nix { }) wal-g-2 wal-g-3;
          inherit (pkgs.cargo-pgrx)
            cargo-pgrx_0_11_3
            cargo-pgrx_0_12_6
            cargo-pgrx_0_12_9
            cargo-pgrx_0_14_3
            ;
        }
        // lib.filterAttrs (n: v: n != "override" && n != "overrideAttrs" && n != "overrideDerivation") (
          pkgs.callPackage ../postgresql/default.nix {
            inherit (pkgs)
              lib
              stdenv
              fetchurl
              makeWrapper
              callPackage
              buildEnv
              newScope
              ;
          }
        )
      );
    };
  flake.overlays.default = final: prev: {
    # NOTE: add any needed overlays here. in theory we could
    # pull them from the overlays/ directory automatically, but we don't
    # want to have an arbitrary order, since it might matter. being
    # explicit is better.
    inherit (self.packages.${final.system})
      postgresql_15
      postgresql_17
      postgresql_orioledb-17
      ;

    xmrig = throw "The xmrig package has been explicitly disabled in this flake.";

    cargo-pgrx = final.callPackage ../cargo-pgrx/default.nix {
      inherit (final) lib;
      inherit (final) darwin;
      inherit (final) fetchCrate;
      inherit (final) openssl;
      inherit (final) pkg-config;
      inherit (final) makeRustPlatform;
      inherit (final) stdenv;
      inherit (final) rust-bin;
    };

    buildPgrxExtension = final.callPackage ../cargo-pgrx/buildPgrxExtension.nix {
      inherit (final) cargo-pgrx;
      inherit (final) lib;
      inherit (final) Security;
      inherit (final) pkg-config;
      inherit (final) makeRustPlatform;
      inherit (final) stdenv;
      inherit (final) writeShellScriptBin;
    };

    buildPgrxExtension_0_11_3 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_11_3;
    };

    buildPgrxExtension_0_12_6 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_6;
    };

    buildPgrxExtension_0_12_9 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_9;
    };

    buildPgrxExtension_0_14_3 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_14_3;
    };
  };
}
