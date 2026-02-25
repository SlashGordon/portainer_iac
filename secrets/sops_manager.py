#!/usr/bin/env python3
"""
SOPS Manager - Native execution for Alpine Containers
Handles encryption/decryption using age keys in a Docker volume.
No .sops.yaml required; builds encryption commands on the fly.
"""

import argparse
import subprocess
import sys
import os
import re
import shutil
from pathlib import Path
from typing import List, Optional
import yaml


class Colors:
    BLUE = "\033[0;34m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RED = "\033[0;31m"
    NC = "\033[0m"


def print_info(msg: str):
    print(f"{Colors.BLUE}ℹ{Colors.NC} {msg}")


def print_success(msg: str):
    print(f"{Colors.GREEN}✓{Colors.NC} {msg}")


def print_warning(msg: str):
    print(f"{Colors.YELLOW}⚠{Colors.NC} {msg}")


def print_error(msg: str):
    print(f"{Colors.RED}✗{Colors.NC} {msg}")


class SOPSManager:
    def __init__(self, work_dir: Path, age_key_file: Path):
        self.work_dir = work_dir
        self.age_key_file = age_key_file
        self.secrets_dir = work_dir / "secrets"

        # Set environment variable so SOPS knows where the private key is
        os.environ["SOPS_AGE_KEY_FILE"] = str(self.age_key_file)

    def get_public_key(self) -> Optional[str]:
        """Extracts the public key from the keys.txt file for on-the-fly encryption"""
        if not self.age_key_file.exists() or self.age_key_file.is_dir():
            return None

        try:
            content = self.age_key_file.read_text()
            # Find the line starting with 'public key: ' or the key starting with 'age1'
            match = re.search(r"(age1[a-z0-9]+)", content)
            return match.group(1) if match else None
        except Exception as e:
            print_error(f"Could not read public key: {e}")
            return None

    def run_sops(self, args: List[str]) -> subprocess.CompletedProcess:
        """Run SOPS binary directly"""
        cmd = ["sops"] + args
        return subprocess.run(cmd, capture_output=True, text=True)

    def run_sops_bytes(self, args: List[str]) -> subprocess.CompletedProcess:
        """Run SOPS but keep stdout/stderr as bytes (needed for binary output)."""
        cmd = ["sops"] + args
        return subprocess.run(cmd, capture_output=True)

    def write_atomic_text(self, target_path: Path, content: str) -> None:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = target_path.with_name(target_path.name + ".tmp")
        tmp_path.write_text(content)
        tmp_path.replace(target_path)

    def write_atomic_bytes(self, target_path: Path, content: bytes) -> None:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = target_path.with_name(target_path.name + ".tmp")
        tmp_path.write_bytes(content)
        tmp_path.replace(target_path)

    def decrypt_to_text(self, encrypted_path: Path) -> Optional[str]:
        decrypted_bytes = self.decrypt_to_bytes(encrypted_path)
        if decrypted_bytes is None:
            return None

        try:
            return decrypted_bytes.decode("utf-8")
        except Exception:
            return decrypted_bytes.decode("utf-8", errors="replace")

    def decrypt_to_bytes(self, encrypted_path: Path) -> Optional[bytes]:
        if not encrypted_path.exists():
            print_error(f"File not found: {encrypted_path}")
            return None

        # For binary-encrypted inputs, forcing output-type=binary ensures we get the
        # original plaintext bytes (instead of a YAML wrapper like `data: ...`).
        result = self.run_sops_bytes(
            ["-d", "--output-type", "binary", str(encrypted_path)]
        )

        if result.returncode != 0:
            err = (
                result.stderr.decode(errors="replace")
                if isinstance(result.stderr, (bytes, bytearray))
                else str(result.stderr)
            )
            print_error(f"Failed: {err.strip()}")
            return None

        if not result.stdout:
            print_error("Failed: SOPS produced no output")
            return None

        return result.stdout

    def sanitize_path_component(self, value: object) -> str:
        s = str(value).strip()
        if not s:
            return "_"
        return re.sub(r"[^A-Za-z0-9._-]+", "_", s)

    def iter_leaf_secrets(
        self, node: object, key_path: List[str]
    ) -> List[tuple[str, str]]:
        """Return list of (filename, value) pairs for scalar leaves.

        Filenames are the underscore-joined key_path.
        """
        items: List[tuple[str, str]] = []

        if node is None:
            return items

        if isinstance(node, dict):
            for k, v in node.items():
                items.extend(
                    self.iter_leaf_secrets(
                        v, key_path + [self.sanitize_path_component(k)]
                    )
                )
            return items

        if isinstance(node, (str, int, float, bool)):
            if not key_path:
                return items
            filename = "_".join(key_path)
            items.append((filename, str(node)))
            return items

        # Fallback: serialize lists/other types as YAML (still one file per leaf node)
        if yaml is not None and key_path:
            filename = "_".join(key_path)
            try:
                serialized = yaml.safe_dump(node, default_flow_style=False).rstrip("\n")
            except Exception:
                serialized = str(node)
            items.append((filename, serialized))
        return items

    def write_secret_file(
        self, relative_path: str, value: str, mode: int = 0o444
    ) -> None:
        target = self.secrets_dir / relative_path
        self.write_atomic_text(target, value)
        try:
            os.chmod(target, mode)
        except Exception:
            pass

    def clean_secrets_dir(self) -> None:
        if not self.secrets_dir.exists():
            return

        # Remove files first
        for p in sorted(self.secrets_dir.rglob("*"), reverse=True):
            try:
                if p.is_file() or p.is_symlink():
                    p.unlink(missing_ok=True)
            except Exception:
                pass

        # Remove now-empty directories (leave top-level)
        for p in sorted(self.secrets_dir.rglob("*"), reverse=True):
            try:
                if p.is_dir():
                    p.rmdir()
            except Exception:
                pass

    def unpack_credentials(self, encrypted_credentials: Path) -> bool:
        if yaml is None:
            print_error(
                "Missing dependency: PyYAML. Rebuild the container (Dockerfile will install it) or install pyyaml locally."
            )
            return False

        decrypted_text = self.decrypt_to_text(encrypted_credentials)
        if decrypted_text is None:
            return False

        try:
            creds = yaml.safe_load(decrypted_text)
        except Exception as e:
            print_error(f"Could not parse decrypted YAML: {e}")
            return False

        if not isinstance(creds, dict):
            print_error("Decrypted credentials is not a YAML mapping")
            return False

        # The decrypted YAML is the source of truth for generated secret files.
        self.clean_secrets_dir()

        ignored_top_level = {"sops", "metadata"}
        wrote = 0
        skipped = 0

        for top_key, top_node in creds.items():
            if str(top_key) in ignored_top_level:
                continue

            service_dir = self.sanitize_path_component(top_key)
            if not isinstance(top_node, dict):
                skipped += 1
                continue

            for filename, value in self.iter_leaf_secrets(top_node, []):
                rel_path = f"{service_dir}/{filename}"
                self.write_secret_file(rel_path, value)
                wrote += 1

        print_success(f"Unpacked {wrote} secret file(s) into: {self.secrets_dir}")
        if skipped:
            print_warning(f"Skipped {skipped} top-level item(s) (not a mapping)")
        return True

    def is_encrypted_filename(self, file_path: Path) -> bool:
        name_lower = file_path.name.lower()
        return name_lower.endswith(".enc.yml") or name_lower.endswith(".enc.yaml")

    def to_encrypted_path(self, plaintext_path: Path) -> Path:
        if self.is_encrypted_filename(plaintext_path):
            return plaintext_path

        name = plaintext_path.name
        if name.lower().endswith(".yml"):
            return plaintext_path.with_name(name[:-4] + ".enc.yml")
        if name.lower().endswith(".yaml"):
            return plaintext_path.with_name(name[:-5] + ".enc.yaml")
        return plaintext_path.with_name(name + ".enc")

    def to_plaintext_path(self, encrypted_path: Path) -> Path:
        if not self.is_encrypted_filename(encrypted_path):
            return encrypted_path

        name = encrypted_path.name
        if name.lower().endswith(".enc.yml"):
            return encrypted_path.with_name(name[:-8] + ".yml")
        if name.lower().endswith(".enc.yaml"):
            return encrypted_path.with_name(name[:-9] + ".yaml")
        return encrypted_path

    def is_encrypted(self, file_path: Path) -> bool:
        try:
            content = file_path.read_text()
            return "sops:" in content and "ENC[" in content
        except:
            return False

    def encrypt_file(self, file_path: Path) -> bool:
        # Convention:
        # - plaintext:  <name>.yml
        # - encrypted:   <name>.enc.yml
        if self.is_encrypted_filename(file_path):
            encrypted_path = file_path
            plaintext_path = self.to_plaintext_path(file_path)
        else:
            plaintext_path = file_path
            encrypted_path = self.to_encrypted_path(file_path)

        if not plaintext_path.exists():
            print_error(f"File not found: {plaintext_path}")
            return False

        # If someone encrypted in-place (plaintext filename but encrypted content), fix naming.
        if self.is_encrypted(plaintext_path) and not self.is_encrypted_filename(
            plaintext_path
        ):
            if encrypted_path.exists():
                print_warning(
                    f"Source is already encrypted, but {encrypted_path.name} already exists. Skipping."
                )
                return True
            plaintext_path.replace(encrypted_path)
            print_success(f"Renamed encrypted file to: {encrypted_path.name}")
            return True

        if encrypted_path.exists():
            print_info(f"Updating encrypted file: {encrypted_path.name}")

        pub_key = self.get_public_key()
        if not pub_key:
            print_error("No public key found in keys.txt. Cannot encrypt.")
            return False

        print_info(
            f"Encrypting: {plaintext_path.name} -> {encrypted_path.name} (using key {pub_key[:12]}...)"
        )

        # Encrypt the whole file (keys + values) by treating the input as binary.
        # This produces a binary ciphertext output, so the resulting *.enc.yml is not human-readable.
        result = self.run_sops_bytes(
            [
                "-e",
                "--age",
                pub_key,
                "--input-type",
                "binary",
                "--output-type",
                "binary",
                str(plaintext_path),
            ]
        )

        if result.returncode == 0:
            if not result.stdout:
                print_error("Failed: SOPS produced no output")
                return False
            self.write_atomic_bytes(encrypted_path, result.stdout)
            print_success(f"Encrypted: {encrypted_path.name}")
            return True
        else:
            err = (
                result.stderr.decode(errors="replace")
                if isinstance(result.stderr, (bytes, bytearray))
                else str(result.stderr)
            )
            print_error(f"Failed: {err.strip()}")
            return False

    def decrypt_file(self, file_path: Path) -> bool:
        # Convention:
        # - encrypted input:  <name>.enc.yml
        # - plaintext output: <name>.yml
        if not file_path.exists():
            # Helpful fallback: if user passed plaintext name, try the encrypted counterpart.
            candidate_enc = self.to_encrypted_path(file_path)
            if candidate_enc.exists():
                file_path = candidate_enc
            else:
                print_error(f"File not found: {file_path}")
                return False

        if self.is_encrypted_filename(file_path):
            encrypted_path = file_path
            plaintext_path = self.to_plaintext_path(file_path)
        else:
            # If user passed plaintext name but the encrypted counterpart exists, decrypt that.
            candidate_enc = self.to_encrypted_path(file_path)
            if candidate_enc.exists() and self.is_encrypted(candidate_enc):
                encrypted_path = candidate_enc
                plaintext_path = file_path
            else:
                encrypted_path = file_path
                plaintext_path = file_path

        # For *.enc.yml we always attempt a decrypt: it may be binary ciphertext and
        # the marker-based `is_encrypted()` check won't work.
        if not self.is_encrypted_filename(encrypted_path):
            if not self.is_encrypted(encrypted_path):
                print_warning(f"Not encrypted: {encrypted_path.name}")
                return True

        print_info(f"Decrypting: {encrypted_path.name} -> {plaintext_path.name}")

        decrypted_text = self.decrypt_to_text(encrypted_path)
        if decrypted_text is None:
            return False

        self.write_atomic_text(plaintext_path, decrypted_text)
        print_success(f"Decrypted: {plaintext_path.name}")
        return True

    def process_directory(self, operation: str) -> dict:
        stats = {"processed": 0, "skipped": 0, "errors": 0}
        if not self.secrets_dir.exists():
            print_error(f"Directory {self.secrets_dir} does not exist.")
            return stats

        all_files = [f for f in self.secrets_dir.rglob("*") if f.is_file()]

        if operation == "encrypt":
            files = [
                f
                for f in all_files
                if f.suffix.lower() in {".yml", ".yaml"}
                and not self.is_encrypted_filename(f)
                and not self.is_encrypted(f)
            ]
            action = self.encrypt_file
        else:
            files = [
                f
                for f in all_files
                if self.is_encrypted_filename(f) or self.is_encrypted(f)
            ]
            action = self.decrypt_file

        for file_path in files:
            if action(file_path):
                stats["processed"] += 1
            else:
                stats["errors"] += 1
        return stats


def generate_age_key(output_file: Path):
    """Generate age encryption key with robust overwrite and directory cleanup"""
    if output_file.exists():
        # Handle Docker creating mount points as directories
        if output_file.is_dir():
            print_warning(f"Found a directory at {output_file}. Removing it...")
            shutil.rmtree(output_file)
        else:
            # Show existing public key
            try:
                content = output_file.read_text()
                for line in content.split("\n"):
                    if "public key:" in line:
                        print(f"{Colors.YELLOW}{line}{Colors.NC}")
            except:
                pass

            confirm = (
                input(
                    f"\n{Colors.RED}⚠ WARNING:{Colors.NC} Overwrite existing key? Files encrypted with the old key will be lost! (y/N): "
                )
                .strip()
                .lower()
            )
            if confirm != "y":
                print_info("Key generation aborted.")
                return
            output_file.unlink()

    output_file.parent.mkdir(parents=True, exist_ok=True)
    print_info("Generating new age key...")

    result = subprocess.run(
        ["age-keygen", "-o", str(output_file)], capture_output=True, text=True
    )

    if result.returncode == 0:
        print_success(f"New key generated: {output_file}")
        if output_file.exists():
            print(f"\n{Colors.GREEN}{output_file.read_text().strip()}{Colors.NC}")
    else:
        print_error(f"Failed: {result.stderr}")


def main():
    parser = argparse.ArgumentParser(description="SOPS Manager (Dockerized Alpine)")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("encrypt").add_argument("file", nargs="?")
    subparsers.add_parser("decrypt").add_argument("file", nargs="?")
    subparsers.add_parser("unpack").add_argument("file", nargs="?")
    subparsers.add_parser("generate-key")

    args = parser.parse_args()

    # Internal path inside container (shared with Docker Volume)
    age_key_file = Path("/home/sopsuser/.config/sops/age/keys.txt")

    if args.command == "generate-key":
        generate_age_key(age_key_file)
        return

    if not age_key_file.exists() or age_key_file.is_dir():
        print_error("Age key not found. Run 'generate-key' first.")
        sys.exit(1)

    manager = SOPSManager(Path.cwd(), age_key_file)

    if args.command == "encrypt":
        if args.file:
            manager.encrypt_file(Path(args.file))
        else:
            manager.process_directory("encrypt")
    elif args.command == "decrypt":
        if args.file:
            manager.decrypt_file(Path(args.file))
        else:
            manager.process_directory("decrypt")
    elif args.command == "unpack":
        encrypted = Path(args.file) if args.file else Path("credentials.enc.yml")
        if not manager.is_encrypted_filename(encrypted):
            encrypted = manager.to_encrypted_path(encrypted)
        ok = manager.unpack_credentials(encrypted)
        sys.exit(0 if ok else 1)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
