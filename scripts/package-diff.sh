#!/usr/bin/env bash
# Decides whether a freshly built image is worth publishing: compares its
# package set (RPMs + Python packages, via syft) with the currently published
# image. Any difference means a new RHEL package, a new ansible-core or a new
# dependency landed, so a new version gets published.
#
#   scripts/package-diff.sh CANDIDATE PUBLISHED
#
# Writes `changed=true|false` to $GITHUB_OUTPUT and a report to
# $GITHUB_STEP_SUMMARY when running in GitHub Actions; always prints the diff.
# FORCE=true marks the image as changed regardless. SYFT overrides the syft
# command (default: syft on PATH).
set -euo pipefail

CANDIDATE="${1:?usage: $0 CANDIDATE PUBLISHED}"
PUBLISHED="${2:?usage: $0 CANDIDATE PUBLISHED}"
SYFT="${SYFT:-syft}"

packages() {
  $SYFT scan "docker:$1" -o json -q | python3 -c '
import json, sys
arts = json.load(sys.stdin)["artifacts"]
rows = sorted({"%s  %s  %s" % (a["type"], a["name"], a["version"]) for a in arts})
print("\n".join(rows))
'
}

packages "$CANDIDATE" > candidate-packages.txt

# Pull the published image; fall back to a local image of that name so the
# script can be exercised without a registry.
if docker pull -q "$PUBLISHED" >/dev/null 2>&1 || docker image inspect "$PUBLISHED" >/dev/null 2>&1; then
  packages "$PUBLISHED" > published-packages.txt
  published_note="$PUBLISHED"
else
  : > published-packages.txt
  published_note="(no published image found: $PUBLISHED)"
fi

changed=false
if ! diff -u published-packages.txt candidate-packages.txt > packages.diff; then
  changed=true
fi
if [ "${FORCE:-false}" = "true" ]; then
  changed=true
fi

echo "published: $published_note"
echo "changed:   $changed"
cat packages.diff

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$changed" >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Package set vs. $published_note"
    echo
    if [ "$changed" = "true" ]; then
      echo "**Changed, publishing.**"
      echo
      echo '```diff'
      cat packages.diff
      echo '```'
    else
      echo "Unchanged, nothing to publish."
    fi
    echo
    echo "<details><summary>Full package list ($(wc -l < candidate-packages.txt | tr -d ' ') entries)</summary>"
    echo
    echo '```'
    cat candidate-packages.txt
    echo '```'
    echo "</details>"
  } >> "$GITHUB_STEP_SUMMARY"
fi
