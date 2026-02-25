# Secrets (SOPS + age)

This folder contains a small Dockerized wrapper around `sops` + `age`.

It manages one source-of-truth YAML file (`credentials.yml`) and produces:
- an encrypted artifact (`credentials.enc.yml`) you can commit
- Docker secret files under `/opt/portainer_iac/secrets/secrets/` via `unpack`

## Prereqs

- Docker
- `./sops-run.sh` executable (`chmod +x sops-run.sh`)

Keys are stored on the host at `~/.config/sops/age/keys.txt` and mounted into the container.

## Files and naming

- Plaintext (ignored by git): `*.yml` / `*.yaml` (example: `credentials.yml`)
- Encrypted (safe to commit): `*.enc.yml` / `*.enc.yaml` (example: `credentials.enc.yml`)

Encryption is whole-file/binary, so the encrypted file does not reveal YAML key names.

## Typical workflow

Generate an `age` key once:

```bash
./sops-run.sh generate-key
```

Encrypt plaintext → encrypted artifact:

```bash
./sops-run.sh encrypt credentials.yml
```

Decrypt encrypted artifact → plaintext:

```bash
./sops-run.sh decrypt credentials.enc.yml
```

Generate Docker secret files from credentials (directory structure follows the YAML structure):

```bash
./sops-run.sh unpack credentials.enc.yml
```

Output directory:

- `/opt/portainer_iac/secrets/secrets/<top-level>/<nested_key_path_joined_with_underscores>`

Example:

- `tunnel.token` → `/opt/portainer_iac/secrets/secrets/tunnel/token`

## Notes

- `unpack` clears `/opt/portainer_iac/secrets/secrets/` before regenerating to avoid stale files.
- If you see permission issues with the key dir: `sudo chown -R $(whoami) ~/.config/sops`
- If you run `./sops-run.sh` via `sudo`, it uses `SUDO_UID/SUDO_GID` and the invoking user’s home so you don’t accidentally build as UID 0 or write keys to `/root`.
