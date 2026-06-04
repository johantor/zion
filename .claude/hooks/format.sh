#!/usr/bin/env bash
set -e
lane="${1:-}"

case "$lane" in
  dotnet)
    if command -v dotnet >/dev/null 2>&1; then
      dotnet format >/dev/null 2>&1 || true
    fi
    ;;
  web)
    if [ -f package.json ]; then
      npm run -s lint:fix >/dev/null 2>&1 || npm run -s format >/dev/null 2>&1 || npm run -s lint >/dev/null 2>&1 || true
    fi
    ;;
  *)
    ;;
esac
