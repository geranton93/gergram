#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile


FLATC_VERSION = "24.12.23"
BUNDLED_FLATC_SHA256 = "6624f308c0955528b7a5f885a62b89e0745cf7f93c5670cd5a3d0f5bb70138b8"


def compiler_for(root, flatc):
    override = flatc or os.environ.get("GERGRAM_FLATC")
    default = root / ".build" / f"flatbuffers-{FLATC_VERSION}" / "flatc"
    selected = Path(override or default).resolve()
    if selected == (root / "scripts/flatc").resolve():
        raise RuntimeError("the bundled flatc is unsupported. Build flatc from source with bash scripts/build-flatc.sh")
    if not selected.is_file() or not os.access(selected, os.X_OK):
        raise RuntimeError(f"flatc {FLATC_VERSION} is missing at {selected}. Run bash scripts/build-flatc.sh or set GERGRAM_FLATC")
    with selected.open("rb") as executable:
        digest = hashlib.sha256()
        for block in iter(lambda: executable.read(128 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() == BUNDLED_FLATC_SHA256:
        raise RuntimeError("the bundled flatc is unsupported. Build flatc from source with bash scripts/build-flatc.sh")
    if sys.platform == "darwin":
        attributes = subprocess.run(["/usr/bin/xattr", str(selected)], check=True, capture_output=True, text=True)
        if "com.apple.quarantine" in attributes.stdout.splitlines():
            raise RuntimeError(f"flatc has macOS quarantine at {selected}. Build flatc from source with bash scripts/build-flatc.sh")
    version = subprocess.run([str(selected), "--version"], check=True, capture_output=True, text=True)
    if version.stdout.strip() != f"flatc version {FLATC_VERSION}":
        raise RuntimeError(f"flatc {FLATC_VERSION} required, got {version.stdout.strip()!r} at {selected}")
    return selected


def prepare(root, flatc=None):
    base = root / "submodules/telegram-ios/submodules/TelegramCore/FlatSerialization"
    models = sorted((base / "Models").glob("*.fbs"))
    if not models:
        raise RuntimeError("FlatSerialization models are missing")
    compiler = compiler_for(root, flatc)
    output = base / "Sources"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="flat-serialization-") as temporary:
        staging = Path(temporary)
        subprocess.run([str(compiler), "--require-explicit-ids", "--swift", "-o", str(staging)]
                       + [str(model) for model in models], check=True)
        generated = list(staging.glob("*.swift"))
        expected = {model.stem + "_generated.swift" for model in models}
        if {path.name for path in generated} != expected or any(path.stat().st_size == 0 for path in generated):
            raise RuntimeError("flatc did not produce complete Swift sources")
        for path in generated:
            destination = output / path.name
            contents = path.read_bytes()
            if destination.is_file() and destination.read_bytes() == contents:
                continue
            staged = destination.with_suffix(".swift.tmp")
            staged.write_bytes(contents)
            os.replace(staged, destination)
        names = {path.name for path in generated}
        for path in output.glob("*.swift"):
            if path.name not in names:
                path.unlink()
    print("FlatSerialization sources prepared; unchanged files preserved.")


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("error: FlatSerialization generation: " + str(error), file=sys.stderr)
        sys.exit(1)
