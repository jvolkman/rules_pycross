#!/bin/bash
set -euo pipefail

checked=0
expected=274b1e6fc1b966d53976333eb90ac94cb07a450a700b455af9fbdf882244b30a
for f in "$@"; do
    case "$f" in
        *.whl) ;;
        *) continue ;;
    esac
    actual=$(sha256sum "$f" 2>/dev/null || shasum -a 256 "$f")
    if [[ "${actual%% *}" != "$expected" ]]; then
        echo "Unexpected sha256 for $f: $actual"
        exit 1
    fi
    echo "OK: $f"
    checked=$((checked + 1))
done

if [[ "$checked" != 2 ]]; then
    echo "Expected 2 wheels, checked $checked: $*"
    exit 1
fi
