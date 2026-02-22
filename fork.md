# Fork Notes: noTreeTeam/postgres

This repository is a fork of [supabase/postgres](https://github.com/supabase/postgres).

## Key Differences from Upstream

| Area | Upstream | This Fork |
|------|----------|-----------|
| TimescaleDB (PG15) | Apache-only (`-DAPACHE_ONLY=1`, v2.9.1) | Full TSL build (v2.20.3, `timescaledb.nix`) |
| TimescaleDB (PG17) | Apache-only | Full TSL build (v2.20.3, `timescaledb.nix`) |
| Publish workflow | ECR + complex CI matrix | Simple GHCR publish via `publish-latest.yml` |
| Image registry | `public.ecr.aws/supabase/postgres` | `ghcr.io/notreeteam/postgres` |

### Files Changed vs Upstream
- `nix/ext/timescaledb.nix` — new file, builds TimescaleDB 2.20.3 with TSL (no `-DAPACHE_ONLY`)
- `flake.nix` (lines ~164–188) — version-specific extension lists using `timescaledb.nix` for all PG versions
- `.github/workflows/publish-latest.yml` — builds both Dockerfile-15 (PG15) and Dockerfile-17 (PG17), pushes to GHCR

## Syncing with Upstream

```sh
git fetch upstream
git merge upstream/develop   # or upstream/main
```

### Merge Conflicts to Expect

1. **`flake.nix`** — Always keep our `extensionsForPG15AndOlder` and `extensionsForPG17` using `timescaledb.nix`, not `timescaledb-2.9.1.nix`. Upstream will try to revert to `timescaledb-2.9.1.nix` (Apache-only).

2. **`nix/ext/timescaledb-2.9.1.nix`** — Upstream may update it; keep it but we don't use it (it's excluded from both PG15 and PG17 extension lists now).

3. **`.github/workflows/`** — Upstream has a large CI matrix; keep our simple `publish-latest.yml` and discard upstream workflow changes unless they add useful test logic.

### After Merging

- If a new PostgreSQL minor version is released (e.g. `15.8.2`), bump the image tag in `publish-latest.yml` and update the CLI constant in `../cli/pkg/config/constants.go`.
- If `timescaledb.nix` version is updated, verify the hash and test that `SHOW timescaledb.license` returns `timescale` (not `apache`) in the built image.

## Version Tagging

PG15 images are tagged as `15.<pg-minor>.<build>` (e.g. `15.8.1.086`).
The `latest` tag always tracks the most recent PG17 build.

To release a new PG15 image: push to `main` — `publish-latest.yml` will build and push both tags automatically.
