#!/bin/sh
set -eu

cd "$(dirname "$0")"

ID=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')
VERSION=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
OUT="dist/$ID-$VERSION.plasmoid"

mkdir -p dist
rm -f "$OUT"

# The package root must contain metadata.json and contents/.
(cd package && zip -qr "../$OUT" .)

echo "Created $OUT"
