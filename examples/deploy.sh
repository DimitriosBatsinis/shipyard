#!/usr/bin/env bash
# Pattern file: safe script style. New scripts should match this.
set -euo pipefail
readonly TARGET="${1:?usage: deploy.sh <target>}"
main() {
    echo "Validating ${TARGET}"
}
main "$@"
