#!/usr/bin/env bash
# This runs only in the approved, main-only macos-release environment.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MACOS_UPDATE_SIGNING_KEY:?Update signing secret is required}"
: "${RELEASE_VERSION:?Release version is required}"
: "${RELEASE_TAG:?Release tag is required}"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$RELEASE_TAG" == "macos-v$RELEASE_VERSION" ]]
output=build/macos-adhoc
feed="$output/update-feed"
mkdir -p "$feed"
cp "$output/Mirror-macOS-$RELEASE_VERSION.zip" "$feed/"
umask 077
key_file=$(mktemp "${RUNNER_TEMP:-/tmp}/mirror-update-key.XXXXXX")
trap 'rm -f "$key_file"' EXIT
# Do not echo, log, or pass private material as command-line arguments.
python3 - "$key_file" <<'PY'
import os,sys
from pathlib import Path
Path(sys.argv[1]).write_text(os.environ['MACOS_UPDATE_SIGNING_KEY'])
PY
unset MACOS_UPDATE_SIGNING_KEY
"$output/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --ed-key-file "$key_file" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/Imperial-lord/mirror/releases/download/$RELEASE_TAG/" \
  -o "$feed/appcast.xml" "$feed"
python3 - "$feed/appcast.xml" <<'PY'
import sys,xml.etree.ElementTree as ET
from pathlib import Path
raw=Path(sys.argv[1]).read_text()
ns={'sparkle':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
enclosure=ET.fromstring(raw).find('./channel/item/enclosure')
assert enclosure is not None and enclosure.get('{'+ns['sparkle']+'}edSignature')
assert '<!-- sparkle-signatures:' in raw and '\nedSignature: ' in raw, 'Signed feed is required'
print('Prepared signed update archive and appcast.')
PY
