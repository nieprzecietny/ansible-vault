#!/usr/bin/env bash
# Integration test for the ansible-vault image, against the fixtures in
# tests/fixtures (vault password "integrationtest"):
#
#   1. secrets.vault.yml, encrypted by an older release of the image
#      (2.21.5-20261105: ansible-core 2.21.5, Python 3.12), still decrypts to
#      secrets.yml byte for byte, so a new image reads existing vaults.
#   2. Encrypting secrets.yml and decrypting it again gives back the original
#      byte for byte.
#
# Files go in and out over stdin/stdout and live only in the container's tmpfs,
# under the same hardening flags as the smoke test; the comparison runs on the
# host.
#
#   scripts/integration-test.sh IMAGE
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: do not rewrite /tmp in --tmpfs

IMAGE="${1:?usage: $0 IMAGE}"
FIXTURES="$(cd "$(dirname "$0")/../tests/fixtures" && pwd)"
export VAULT_PASSWORD=integrationtest
# shellcheck disable=SC2054  # the commas are tmpfs mount options, one array element
HARDEN=(--rm --network none --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m
        --cap-drop ALL --security-opt no-new-privileges)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

same() { # expected actual what
  if ! cmp -s "$1" "$2"; then
    echo "FAIL: $3 differs from the original:"
    diff -u "$1" "$2" || true
    exit 1
  fi
}

echo "== a vault from an older release decrypts to the original, byte for byte"
docker run "${HARDEN[@]}" -i --user 4321:4321 -e VAULT_PASSWORD --entrypoint bash "$IMAGE" -ec '
  cd /tmp
  cat > v.yml
  printf "%s\n" "$VAULT_PASSWORD" > p
  ansible-vault decrypt v.yml --vault-password-file p >&2
  cat v.yml
' < "$FIXTURES/secrets.vault.yml" > "$work/decrypted.yml"
same "$FIXTURES/secrets.yml" "$work/decrypted.yml" "the decrypted old vault"

echo "== encrypt then decrypt gives back the original, byte for byte"
docker run "${HARDEN[@]}" -i --user 4321:4321 -e VAULT_PASSWORD --entrypoint bash "$IMAGE" -ec '
  cd /tmp
  cat > v.yml
  printf "%s\n" "$VAULT_PASSWORD" > p
  ansible-vault encrypt v.yml --vault-password-file p >&2
  IFS= read -r header < v.yml
  [ "$header" = "\$ANSIBLE_VAULT;1.1;AES256" ] || { echo "FAIL: not a vault after encrypt: $header" >&2; exit 1; }
  if grep -q integration-marker v.yml; then echo "FAIL: plaintext visible in the vault" >&2; exit 1; fi
  ansible-vault decrypt v.yml --vault-password-file p >&2
  cat v.yml
' < "$FIXTURES/secrets.yml" > "$work/roundtrip.yml"
same "$FIXTURES/secrets.yml" "$work/roundtrip.yml" "the encrypted and decrypted file"

echo "integration test OK"
