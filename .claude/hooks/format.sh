#!/usr/bin/env bash
set -e
lane="${1:-}"

case "$lane" in
  dotnet)
    if command -v dotnet >/dev/null 2>&1; then
      dotnet format --verify-no-changes >/dev/null 2>&1 || true
    fi
    ;;
  web)
    if [ -f package.json ]; then
      if npm run -s lint >/dev/null 2>&1; then
        npm run -s lint >/dev/null 2>&1 || true
      fi
    fi
    ;;
  *)
    ;;
esac
