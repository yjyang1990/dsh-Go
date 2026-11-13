#!/usr/bin/env bash
# Dedicated side-by-side install with a complete bundled arm64 runtime.
# Keep the signing files outside the repository. Uses the normal APK builder.
# Usage: tooling/build-preview.sh [--dry-run] [--build-name X.Y.Z-preview]
set -euo pipefail
ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 -I "$ROOT/tooling/check_runtime_bundle.py" arm64
export DSH_GO_PREVIEW=1
export DSH_GO_PREVIEW_SIGNING=${DSH_GO_PREVIEW_SIGNING:-${HOME:?}/.config/dsh-go-preview/signing.properties}
exec bash "$ROOT/tooling/build-apk.sh" --profile -f arm64 --keep-daemon \
  --build-name 1.0.16-preview "$@" -- --no-pub --dart-define=DSH_GO_PREVIEW=true
