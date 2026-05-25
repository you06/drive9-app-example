#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
DRIVE9_DIR="${DRIVE9_REPO:-$VENDOR/drive9}"

mkdir -p "$VENDOR"

if [[ -d "$DRIVE9_DIR/.git" ]]; then
    git -C "$DRIVE9_DIR" fetch --all --prune
    git -C "$DRIVE9_DIR" checkout sdk-ci
    git -C "$DRIVE9_DIR" pull --ff-only
else
    git clone git@github.com:you06/drive9.git "$DRIVE9_DIR"
    git -C "$DRIVE9_DIR" checkout sdk-ci
fi

echo "Drive9 SDK checkout: $DRIVE9_DIR"
echo "Next: follow ios/README.md or android/README.md"

