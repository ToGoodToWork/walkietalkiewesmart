#!/usr/bin/env bash
# Generate WalkieTalk.xcodeproj from project.yml using XcodeGen,
# then open it in Xcode. Run this once after cloning the repo.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> XcodeGen not found; installing via Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew not installed. See https://brew.sh"
    exit 1
  fi
  brew install xcodegen
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Opening Xcode"
open WalkieTalk.xcodeproj

cat <<'EOF'

Once Xcode opens:
  1. Signing & Capabilities tab → set Team to your personal Apple ID team.
  2. Select an iPhone Simulator (e.g. iPhone 15) as the destination.
  3. Cmd+R to build and run.

The Debug build hits http://localhost:3000.
Make sure your local backend is running:
  cd ../backend
  docker compose -f ../docker-compose.dev.yml up -d
  npm install && npm run migrate:dev && npm run seed:dev
  npm run dev
EOF
