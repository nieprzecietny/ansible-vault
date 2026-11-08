#!/usr/bin/env bash
# Installs the latest release of a GitHub project's command-line tool through
# the GitHub API (`gh release download`), checked against the release's sha256
# checksum file.
#
# The publish workflow uses it as a fallback when an installer action fails:
# those actions download from github.com/<repo>/releases/download, which
# returned HTTP 504 for hours on 2026-11-08 while the API kept working.
#
#   scripts/install-release-binary.sh REPO ASSET CHECKSUMS BINARY
#
#   REPO       owner/name, e.g. anchore/syft
#   ASSET      glob of the release asset: the binary itself or a .tar.gz with BINARY inside
#   CHECKSUMS  glob of the release's sha256 checksum file
#   BINARY     name of the installed command
#
# Installs into $RUNNER_TEMP/bin (./bin outside Actions), adds that directory
# to $GITHUB_PATH when set and prints the path of the installed binary.
# Needs gh and GH_TOKEN.
set -euo pipefail

REPO="${1:?usage: $0 REPO ASSET CHECKSUMS BINARY}"
ASSET="${2:?usage: $0 REPO ASSET CHECKSUMS BINARY}"
CHECKSUMS="${3:?usage: $0 REPO ASSET CHECKSUMS BINARY}"
BINARY="${4:?usage: $0 REPO ASSET CHECKSUMS BINARY}"

bin="${RUNNER_TEMP:-$PWD}/bin"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$bin"

gh release download --repo "$REPO" --dir "$work" --pattern "$ASSET" --pattern "$CHECKSUMS" >&2

shopt -s nullglob
# shellcheck disable=SC2206  # ASSET and CHECKSUMS are globs: expanding them is the point
assets=("$work"/$ASSET)
# shellcheck disable=SC2206
sums=("$work"/$CHECKSUMS)
[ "${#assets[@]}" -eq 1 ] || { echo "expected one asset matching $ASSET in $REPO, got ${#assets[@]}" >&2; exit 1; }
[ "${#sums[@]}" -eq 1 ] || { echo "expected one checksum file matching $CHECKSUMS in $REPO, got ${#sums[@]}" >&2; exit 1; }
asset="$(basename "${assets[0]}")"

# Check exactly the downloaded asset against its line in the checksum file.
( cd "$work" && grep -E "^[0-9a-f]{64}  \*?$asset\$" "${sums[0]}" | sha256sum --check --strict >&2 )

case "$asset" in
  *.tar.gz) tar -xzf "$work/$asset" -C "$work" "$BINARY"; src="$work/$BINARY" ;;
  *)        src="$work/$asset" ;;
esac
install -m 0755 "$src" "$bin/$BINARY"

[ -n "${GITHUB_PATH:-}" ] && echo "$bin" >> "$GITHUB_PATH"
echo "installed $bin/$BINARY from $REPO ($asset, checksum OK)" >&2
echo "$bin/$BINARY"
