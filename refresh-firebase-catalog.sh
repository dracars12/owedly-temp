#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/tools/full-snapshot"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm are required. Install Node.js first, then run this script again."
  exit 1
fi

if [ ! -d node_modules ]; then
  npm install
fi

npm run snapshot

echo
echo "Ready to import into Firebase Realtime Database:"
echo "$ROOT/realtime-database.full.json"
