# Use the TimescaleDB version from nixpkgs instead of building from source
# This provides TimescaleDB 2.19.3+ and avoids build times

{ lib, postgresql, stdenv }:

# Simply use the timescaledb-apache from nixpkgs
# This is already compiled and tested
postgresql.pkgs.timescaledb-apache or
# Fallback if for some reason it's not available
(throw "TimescaleDB not available in nixpkgs for PostgreSQL ${postgresql.version}")
