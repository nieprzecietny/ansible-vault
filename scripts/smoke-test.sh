#!/usr/bin/env bash
# Smoke test for the ansible-vault image. Runs everything under the same
# hardening flags the README recommends, so the test also proves those work.
#
#   scripts/smoke-test.sh IMAGE
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: do not rewrite /tmp in --tmpfs

IMAGE="${1:?usage: $0 IMAGE}"
# shellcheck disable=SC2054  # the commas are tmpfs mount options, one array element
HARDEN=(--rm --network none --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m
        --cap-drop ALL --security-opt no-new-privileges)

echo "== version"
docker run "${HARDEN[@]}" "$IMAGE" --version | head -1

echo "== default user is unprivileged"
uid="$(docker run "${HARDEN[@]}" --entrypoint id "$IMAGE" -u | tr -d '\r')"
[ "$uid" = "1000" ] || { echo "expected uid 1000, got $uid"; exit 1; }

echo "== encrypt / view / decrypt / encrypt_string round trip as an arbitrary UID"
docker run "${HARDEN[@]}" --user 4321:4321 --entrypoint bash "$IMAGE" -ec '
  cd /tmp
  printf "secret: hunter2\n" > v.yml
  printf "testpass\n" > p
  ansible-vault encrypt v.yml --vault-password-file p
  grep -q "^\$ANSIBLE_VAULT;1.1;AES256" v.yml
  ansible-vault view v.yml --vault-password-file p | grep -q "^secret: hunter2$"
  ansible-vault decrypt v.yml --vault-password-file p
  grep -q "^secret: hunter2$" v.yml
  printf "hunter2" | ansible-vault encrypt_string --vault-password-file p --stdin-name my_secret | grep -q "^my_secret: !vault"
'

echo "== view through a pseudo-TTY (the pager code path) prints the plaintext"
out="$(docker run "${HARDEN[@]}" -t --user 4321:4321 --entrypoint bash "$IMAGE" -ec '
  cd /tmp
  printf "secret: hunter2\n" > v.yml
  printf "testpass\n" > p
  ansible-vault encrypt v.yml --vault-password-file p >/dev/null
  ansible-vault view v.yml --vault-password-file p
' | tr -d '\r')"
printf '%s\n' "$out" | grep -q "secret: hunter2" || { echo "unexpected view output:"; printf '%s\n' "$out"; exit 1; }
if printf '%s\n' "$out" | grep -qi "not found"; then echo "pager error in view output:"; printf '%s\n' "$out"; exit 1; fi

echo "== nothing but ansible-vault is present"
docker run "${HARDEN[@]}" --entrypoint bash "$IMAGE" -ec '
  for b in vi vim nano less more pip pip3 dnf microdnf yum rpm curl wget git ssh \
           ansible ansible-playbook ansible-galaxy ansible-pull ansible-console ansible-doc ansible-test; do
    if command -v "$b" >/dev/null 2>&1; then echo "unexpected binary present: $b"; exit 1; fi
  done
  entries="$(ls /usr/local/bin)"
  [ "$entries" = "ansible-vault" ] || { echo "unexpected entry points: $entries"; exit 1; }
  test -d /usr/lib/sysimage/rpm || { echo "RPM database missing (scanners would be blind)"; exit 1; }
  . /etc/os-release && echo "$PRETTY_NAME"
'

echo "smoke test OK"
