# ansible-vault in a container

[![publish](https://github.com/nieprzecietny/ansible-vault/actions/workflows/publish.yml/badge.svg)](https://github.com/nieprzecietny/ansible-vault/actions/workflows/publish.yml)

`ansible-vault` and nothing else: encrypt, decrypt, view and rekey Ansible Vault files without
installing Ansible. The image is a minimal RHEL 10 (Red Hat UBI) root filesystem with Python and
`ansible-core`, rebuilt and rescanned every day and published only when something inside changed.

- Docker Hub: `nieprzecietnykowalski/ansible-vault`
- GitHub Container Registry: `ghcr.io/nieprzecietny/ansible-vault`

| Tag | Meaning |
|---|---|
| `latest` | newest build |
| `2.21` | newest build of that ansible-core minor |
| `2.21.5` | newest build of that ansible-core version |
| `2.21.5-20261009` | that version as built on that day (a rebuild on the same day overwrites it) |

## Usage

Mount the directory with your vault files at `/work` and pass any `ansible-vault` arguments.
The container needs no network, no write access outside `/work` and `/tmp`, and no Linux
capabilities, so the examples take all of them away.

PowerShell:

```powershell
docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges -v "${PWD}:/work" nieprzecietnykowalski/ansible-vault view secrets.yml
```

Bash / zsh on Linux and macOS:

```bash
docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges --user "$(id -u):$(id -g)" -v "$(pwd):/work" nieprzecietnykowalski/ansible-vault view secrets.yml
```

cmd.exe:

```cmd
docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges -v "%cd%:/work" nieprzecietnykowalski/ansible-vault view secrets.yml
```

`-it` is needed whenever the command asks for the password or prints to the screen (`view`).
On Linux, `--user "$(id -u):$(id -g)"` keeps the files you encrypt owned by you; the image runs
under any UID.

### Make it a command

PowerShell profile (`notepad $PROFILE`):

```powershell
function ansible-vault {
    docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges `
        -v "${PWD}:/work" nieprzecietnykowalski/ansible-vault @args
}
```

Bash / zsh (`~/.bashrc`, `~/.zshrc`):

```bash
ansible-vault() {
    docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
        --user "$(id -u):$(id -g)" -v "$(pwd):/work" nieprzecietnykowalski/ansible-vault "$@"
}
```

Git Bash on Windows (MSYS rewrites paths, so turn that off and pass a Windows path):

```bash
ansible-vault() {
    MSYS_NO_PATHCONV=1 docker run --rm -it --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
        -v "$(pwd -W):/work" nieprzecietnykowalski/ansible-vault "$@"
}
```

Then simply `ansible-vault encrypt secrets.yml`, `ansible-vault view secrets.yml`, and so on.

### Supported commands

| Command | Example |
|---|---|
| `encrypt` | `encrypt secrets.yml` |
| `decrypt` | `decrypt secrets.yml` |
| `view` | `view secrets.yml` |
| `rekey` | `rekey secrets.yml` |
| `encrypt_string` | `encrypt_string --stdin-name db_password` (type the value, finish with Ctrl-D) |

`edit` and `create` are **not supported**: the image ships no editor on purpose. Decrypt, edit the
file locally, encrypt again.

For scripts, feed `encrypt_string` through a pipe and drop `-t`:

```bash
printf '%s' 'the-value' | docker run --rm -i --network none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
    -v "$(pwd):/work" nieprzecietnykowalski/ansible-vault encrypt_string --stdin-name db_password --vault-password-file .vault_pass
```

### Passwords

- **Prompt** (default): needs `-it`.
- **Password file**: `--vault-password-file .vault_pass` with the file inside the mounted directory.
  Never commit it; add it to your `.gitignore`.
- **Environment**: Ansible also honours `ANSIBLE_VAULT_PASSWORD_FILE`; pass it with `-e`.

Docker Desktop for Windows shows every bind-mounted file as executable (mode `0777`), so Ansible
treats `.vault_pass` as a *script* and fails with `Exec format error`. Make the file a real script
that prints the password, with LF line endings:

```sh
#!/bin/sh
echo my-vault-password
```

## What is inside, and what is not

Inside:

- RHEL 10 UBI packages: `bash`, `coreutils-single`, `python3` and their dependencies, installed
  straight from the UBI repositories at build time. The RPM database is kept so scanners see every package.
- `ansible-core` and its eight Python dependencies, pinned with hashes in `requirements.txt`.
- One entry point, `/usr/local/bin/ansible-vault`. The other ansible CLIs are removed.
- An unprivileged default user (`ansible`, UID 1000). `ANSIBLE_HOME` points at `/tmp`.

Not inside: a package manager (`dnf`, `microdnf`, `rpm`), `pip`, editors, a pager, `curl`, `wget`,
`git`, `ssh`, root as default user. `scripts/smoke-test.sh` checks all of this on every build.

The container runs with `--network none`, `--read-only` plus `--tmpfs /tmp` (decrypted temporary
data stays in memory), `--cap-drop ALL`, `--security-opt no-new-privileges` and any `--user`.

### Verify what you pull

Every published image is signed with cosign (keyless, GitHub OIDC) and carries an SBOM and SLSA
provenance attestation produced by the build.

```bash
cosign verify nieprzecietnykowalski/ansible-vault:latest \
  --certificate-identity-regexp '^https://github.com/nieprzecietny/ansible-vault/\.github/workflows/publish\.yml@refs/heads/master$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect nieprzecietnykowalski/ansible-vault:latest --format '{{ json .SBOM }}'
```

## How updates happen (no human in the loop)

1. **Daily at 05:17 UTC, and on every push to `master`**, the `publish` workflow builds the image
   from scratch (no layer cache, so the newest RHEL packages are picked up), runs the smoke test,
   scans it with Trivy and Grype (results land in the repository's Security tab) and compares its
   package set with the published `latest` using syft.
2. **If anything changed** (RHEL errata, a new `ansible-core`, a new dependency) a new version is
   pushed to both registries, signed, and tagged as in the table above. Each run's summary lists
   the package diff. If nothing changed, nothing is published.
3. **Dependabot** opens pull requests for the UBI builder image digest, for `ansible-core` and its
   dependencies (`requirements.txt`, hashes included, security updates as soon as an advisory is
   out) and for the GitHub Actions. They are merged automatically once the `ci` check (build,
   smoke test, scans) is green, and the next `publish` run ships them.

To publish by hand: Actions, `publish`, *Run workflow* (tick *force* to publish an unchanged image).

## Build and test locally

```bash
docker build -t ansible-vault:dev .
scripts/smoke-test.sh ansible-vault:dev
```

To change the `ansible-core` version, edit `requirements.in` and regenerate the pinned file:

```bash
pip-compile --generate-hashes --strip-extras -o requirements.txt requirements.in
```
