{
  runCommand,
  psql_15,
  psql_17,
  psql_orioledb-17,
  pgsqlDefaultPort,
  pgsqlSuperuser,
}:
let
  migrationsDir = ./migrations/db;
  postgresqlSchemaSql = ./nix/tools/postgresql_schema.sql;
  pgbouncerAuthSchemaSql = ./ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
  statExtensionSql = ./ansible/files/stat_extension.sql;
in
runCommand "start-postgres-client" { } ''
  mkdir -p $out/bin
  substitute ${./run-client.sh.in} $out/bin/start-postgres-client \
    --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
    --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
    --subst-var-by 'PSQL15_BINDIR' '${psql_15.bin}' \
    --subst-var-by 'PSQL17_BINDIR' '${psql_17.bin}' \
    --subst-var-by 'PSQLORIOLEDB17_BINDIR' '${psql_orioledb-17.bin}' \
    --subst-var-by 'MIGRATIONS_DIR' '${migrationsDir}' \
    --subst-var-by 'POSTGRESQL_SCHEMA_SQL' '${postgresqlSchemaSql}' \
    --subst-var-by 'PGBOUNCER_AUTH_SCHEMA_SQL' '${pgbouncerAuthSchemaSql}' \
    --subst-var-by 'STAT_EXTENSION_SQL' '${statExtensionSql}'
  chmod +x $out/bin/start-postgres-client
''
