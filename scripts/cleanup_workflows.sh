#!/usr/bin/env bash
# Remove upstream GitHub workflows that are not needed in this fork.
set -euo pipefail

WORKFLOWS=(
  ".github/workflows/ami-release-nix-single.yml"
  ".github/workflows/ami-release-nix.yml"
  ".github/workflows/check-shellscripts.yml"
  ".github/workflows/ci.yml"
  ".github/workflows/dockerhub-release-matrix.yml"
  ".github/workflows/manual-docker-release.yml"
  ".github/workflows/mirror-postgrest.yml"
  ".github/workflows/mirror.yml"
  ".github/workflows/nix-build.yml"
  ".github/workflows/publish-migrations-prod.yml"
  ".github/workflows/publish-migrations-staging.yml"
  ".github/workflows/publish-nix-pgupgrade-bin-flake-version.yml"
  ".github/workflows/publish-nix-pgupgrade-scripts.yml"
  ".github/workflows/qemu-image-build.yml"
  ".github/workflows/test.yml"
  ".github/workflows/testinfra-ami-build.yml"
)

DIRS=(
  ".github/actions/shared-checkout"
)

echo "Cleaning up upstream workflows..."
for wf in "${WORKFLOWS[@]}"; do
  if [ -e "$wf" ]; then
    echo "Removing $wf"
    rm -f "$wf"
  fi
done

for dir in "${DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "Removing $dir"
    rm -rf "$dir"
  fi
done

echo "Done."
