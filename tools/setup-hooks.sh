#!/usr/bin/env bash
# Enables the repo's git hooks (.githooks/) for this clone: once per clone.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$ROOT" config core.hooksPath .githooks
chmod +x "$ROOT/.githooks/"* "$ROOT/tools/"*.sh 2>/dev/null || true
echo "Hooks activados: antes de cada push se corren los tests (tools/run-tests.sh)."
