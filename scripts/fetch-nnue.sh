#!/usr/bin/env bash
#
# Downloads the Stockfish NNUE nets the iOS app bundles into
# iOS/Motif/Motif/Engine/Nets/ (git-ignored: ~75 MB). Each file's SHA-256 must
# start with the hex in its name. Nets already present and intact are left alone.
# See "Motif - iOS Eval Bar Plan.md" §2.
#
#   scripts/fetch-nnue.sh                    # fetch whatever is missing
#   scripts/fetch-nnue.sh --names            # print the net names (CI cache key)
#   scripts/fetch-nnue.sh --check-ipa X.ipa  # fail unless the IPA carries every net
#
# Written for macOS's bash 3.2: no associative arrays, no GNU-only flags.

set -euo pipefail
cd "$(dirname "$0")/.."

# The only place the names live. They must be the ones the pinned
# ChessKitEngine's Stockfish expects (EvalFileDefaultNameBig/Small in its
# evaluate.h), because the package looks them up in the app bundle by name.
NETS="nn-1111cefa1111.nnue nn-37f18f62d772.nnue"
DIR="iOS/Motif/Motif/Engine/Nets"
URL="https://tests.stockfishchess.org/api/nn"

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -c1-64
}

# nn-<first 12 hex of the SHA-256>.nnue
intact() {
  local want="${1#nn-}"
  want="${want%.nnue}"
  [ -s "$2" ] && [ "$(sha256 "$2" | cut -c1-${#want})" = "$want" ]
}

case "${1:-}" in
  --names)
    echo "$NETS"
    exit 0
    ;;
  --check-ipa)
    ipa="${2:?usage: fetch-nnue.sh --check-ipa X.ipa}"
    listing=$(unzip -l "$ipa")
    for net in $NETS; do
      if ! echo "$listing" | grep -Eq "Payload/[^/]+\.app/$net\$"; then
        echo "error: $ipa has no $net; the app must not ship without its nets" >&2
        exit 1
      fi
    done
    echo "== $ipa carries $NETS"
    exit 0
    ;;
  "") ;;
  *)
    echo "usage: fetch-nnue.sh [--names | --check-ipa X.ipa]" >&2
    exit 2
    ;;
esac

mkdir -p "$DIR"
for net in $NETS; do
  path="$DIR/$net"
  if intact "$net" "$path"; then
    echo "== $net present"
    continue
  fi
  echo "== fetching $net"
  # Outside the synchronized folder, so a broken download never lands in the bundle.
  tmp=$(mktemp)
  curl -fL --retry 3 --silent --show-error -o "$tmp" "$URL/$net"
  if ! intact "$net" "$tmp"; then
    rm -f "$tmp"
    echo "error: $net failed its SHA-256 check" >&2
    exit 1
  fi
  chmod 644 "$tmp"
  mv "$tmp" "$path"
done
