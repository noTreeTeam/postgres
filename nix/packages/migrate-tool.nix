{ runCommand, psql_15 }:
let
  configFile = ./nix/tests/postgresql.conf.in;
  getkeyScript = ./nix/tests/util/pgsodium_getkey.sh;
  primingScript = ./nix/tests/prime.sql;
  migrationData = ./nix/tests/migrations/data.sql;
in
runCommand "migrate-postgres" { } ''
  mkdir -p $out/bin
  substitute ${./nix/tools/migrate-tool.sh.in} $out/bin/migrate-postgres \
    --subst-var-by 'PSQL15_BINDIR' '${psql_15.bin}' \
    --subst-var-by 'PSQL_CONF_FILE' '${configFile}' \
    --subst-var-by 'PGSODIUM_GETKEY' '${getkeyScript}' \
    --subst-var-by 'PRIMING_SCRIPT' '${primingScript}' \
    --subst-var-by 'MIGRATION_DATA' '${migrationData}'

  chmod +x $out/bin/migrate-postgres
''
