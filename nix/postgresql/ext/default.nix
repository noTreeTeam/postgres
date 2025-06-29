# PostgreSQL extensions for this project
# This file imports all custom extensions and makes them available to PostgreSQL packages

self: super:

let
  # Import our custom extensions from the parent ext directory
  extDir = ../../ext;
  
  # Function to build an extension using callPackage
  buildExtension = path: self.callPackage path { };
  
  # List of our extensions (filtered by flake logic)
  ourExtensions = [
    (extDir + "/rum.nix")
    (extDir + "/timescaledb.nix")
    (extDir + "/timescaledb-2.9.1.nix")
    (extDir + "/pgroonga.nix")
    (extDir + "/index_advisor.nix")
    (extDir + "/wal2json.nix")
    (extDir + "/pgmq.nix")
    (extDir + "/pg_repack.nix")
    (extDir + "/pg-safeupdate.nix")
    (extDir + "/plpgsql-check.nix")
    (extDir + "/hypopg.nix")
    (extDir + "/pgaudit.nix")
    (extDir + "/pgtap.nix")
    (extDir + "/pg_cron.nix")
    (extDir + "/pgvector.nix")
    (extDir + "/pgsodium.nix")
    (extDir + "/supautils.nix")
    (extDir + "/vault.nix")
    (extDir + "/pg_graphql.nix")
    (extDir + "/pg_jsonschema.nix")
    (extDir + "/pg_net.nix")
    (extDir + "/pg_hashids.nix")
    (extDir + "/pgjwt.nix")
    (extDir + "/pg_tle.nix")
    (extDir + "/pgsql-http.nix")
    (extDir + "/pg_stat_monitor.nix")
    (extDir + "/pg_partman.nix")
    (extDir + "/postgis.nix")
    (extDir + "/plv8.nix")
    (extDir + "/pg_plan_filter.nix")
    (extDir + "/pljava.nix")
    (extDir + "/orioledb.nix")
  ];

in

# Build all extensions and make them available
builtins.listToAttrs (map
  (extPath: 
    let 
      ext = buildExtension extPath;
    in 
    { 
      name = ext.pname; 
      value = ext; 
    }
  )
  ourExtensions)
