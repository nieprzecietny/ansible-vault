# Ansible Vault Docker Image

This directory contains a Dockerfile to build a lightweight image for running `ansible-vault` commands
without needing to install Ansible on your local machine.

## Build the Image

Run the following command in this directory:

```bash
docker build -t ansible-vault .
```

## Usage

The container is configured with `ansible-vault` as the entrypoint. You need to mount your current directory to `/work` inside the container to access your files.

Here are examples for different shells to run `ansible-vault` commands inside the container.

### Bash (Linux / macOS / Git Bash)

Use `$(pwd)` to mount the current directory.

**Syntax:**
```bash
docker run --rm -it -v "$(pwd):/work" ansible-vault [COMMAND] [ARGS]
```

**Example - View an encrypted file:**
```bash
docker run --rm -it -v "$(pwd):/work" ansible-vault view secrets.yml
```

### PowerShell (Windows)

Use `${PWD}` to mount the current directory.

**Syntax:**
```powershell
docker run --rm -it -v "${PWD}:/work" ansible-vault [COMMAND] [ARGS]
```

**Example - View an encrypted file:**
```powershell
docker run --rm -it -v "${PWD}:/work" ansible-vault view secrets.yml
```

### Command Prompt (Windows cmd.exe)

Use `%cd%` to mount the current directory.

**Syntax:**
```cmd
docker run --rm -it -v "%cd%:/work" ansible-vault [COMMAND] [ARGS]
```

**Example - View an encrypted file:**
```cmd
docker run --rm -it -v "%cd%:/work" ansible-vault view secrets.yml
```

## Common Commands

Replace `[COMMAND]` and `[ARGS]` in the examples above with one of the following:

**1. Encrypt a file:**
`encrypt secrets.yml`

**2. Decrypt a file:**
`decrypt secrets.yml`

**3. Edit an encrypted file:**
`edit secrets.yml`

**4. Encrypt with a password file:**
`encrypt secrets.yml --vault-password-file .vault_pass` (ensure `.vault_pass` is in the current directory)

## User Permissions

The container runs as a non-root user `ansible` (UID 1000). Ensure your local files have appropriate permissions if you encounter access issues.
