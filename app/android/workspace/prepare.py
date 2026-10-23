#!/usr/bin/env python3
"""Prepares the Android Linux workspace that the APK carries.

Android 10+ only lets an app execute files from its native library folder,
so every program the app starts is packaged as a lib*.so under
src/main/jniLibs/<abi>/ and extracted at install (useLegacyPackaging):

  libproot.so          proot (Termux build, GPL-2.0), runs the Ubuntu guest
  libproot_loader.so   proot's loader; maps guest programs instead of exec
  libtalloc.so, libandroid-shmem.so   proot's libraries
  liblookd.so          lookd for linux/<arch>, run inside the guest

The agent's sources go to src/main/assets/look/agent.tgz; its npm
dependencies are installed on the device by lookd's runtime setup.

Usage: prepare.py [--abi arm64-v8a,x86_64] [--skip-lookd] [--skip-agent]
Outputs are build artifacts and stay out of Git (see .gitignore).
Contract: docs/specs/draft-android-app.md
"""

import argparse
import hashlib
import io
import lzma
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent.parent  # look-studio/app
REPO = APP.parent  # look-studio
MAIN = APP / "android" / "app" / "src" / "main"

MIRRORS = [
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main/",
    "https://packages.termux.dev/apt/termux-main/",
]

# Termux packages, pinned by version and SHA-256 (Packages index of
# termux-main stable). Sources: https://github.com/termux/proot,
# https://github.com/termux/termux-packages
DEBS = {
    "aarch64": {
        "proot": ("pool/main/p/proot/proot_5.1.107.98_aarch64.deb",
                  "29de40efea4daa2a6168b617915206511c63e8d46bf5f4b07d48723441ef7f3b"),
        "libtalloc": ("pool/main/libt/libtalloc/libtalloc_2.5.0_aarch64.deb",
                      "556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7"),
        "libandroid-shmem": ("pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_aarch64.deb",
                             "0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6"),
    },
    "x86_64": {
        "proot": ("pool/main/p/proot/proot_5.1.107.98_x86_64.deb",
                  "1c31ad7e1046f4d418fef19b6dfaa9a14801d2047ade6ad0375b3f5501e3e227"),
        "libtalloc": ("pool/main/libt/libtalloc/libtalloc_2.5.0_x86_64.deb",
                      "b8c6d95f20075dc1f9ec6573575b2444e8d526e48e0d8d6d5cf4e071e6e06530"),
        "libandroid-shmem": ("pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_x86_64.deb",
                             "ffa9e4c87467b158b148d0ff92dda796aa038276c2075af3269cdcdb06f25797"),
    },
}

ABIS = {"arm64-v8a": ("aarch64", "arm64"), "x86_64": ("x86_64", "amd64")}
PREFIX = "data/data/com.termux/files/usr/"
CACHE = HERE / ".cache"


def fetch(rel: str, sha: str) -> bytes:
    dest = CACHE / Path(rel).name
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == sha:
        return dest.read_bytes()
    err = None
    for m in MIRRORS:
        try:
            with urllib.request.urlopen(m + rel, timeout=60) as r:
                b = r.read()
        except OSError as e:
            err = e
            continue
        if hashlib.sha256(b).hexdigest() != sha:
            err = RuntimeError(f"{rel}: checksum mismatch from {m}")
            continue
        CACHE.mkdir(exist_ok=True)
        dest.write_bytes(b)
        return b
    raise SystemExit(f"cannot fetch {rel}: {err}")


def deb_files(deb: bytes) -> dict:
    """Regular files and symlinks of a .deb's data archive by path."""
    assert deb[:8] == b"!<arch>\n", "not a deb"
    pos, data = 8, None
    while pos < len(deb):
        name = deb[pos:pos + 16].decode().strip().rstrip("/")
        size = int(deb[pos + 48:pos + 58].decode().strip())
        body = deb[pos + 60:pos + 60 + size]
        if name.startswith("data.tar"):
            data = body
        pos += 60 + size + (size & 1)
    raw = lzma.decompress(data) if data[:6] == b"\xfd7zXZ\x00" else data
    out = {}
    with tarfile.open(fileobj=io.BytesIO(raw)) as t:
        for m in t.getmembers():
            p = m.name.lstrip("./")
            if m.issym():
                out[p] = ("link", m.linkname)
            elif m.isfile():
                out[p] = ("file", t.extractfile(m).read())
    return out


def resolve(files: dict, path: str) -> bytes:
    for _ in range(8):
        kind, v = files[path]
        if kind == "file":
            return v
        path = os.path.normpath(os.path.join(os.path.dirname(path), v))
    raise SystemExit(f"symlink loop at {path}")


def rename_needed(elf: bytes, old: str, new: str) -> bytes:
    """Points DT_NEEDED/DT_SONAME at a shorter name in place: Android only
    extracts libraries named lib*.so, so versioned names cannot ship."""
    a, b = old.encode() + b"\0", new.encode() + b"\0"
    assert len(b) <= len(a)
    if a not in elf:
        return elf
    return elf.replace(a, b + b"\0" * (len(a) - len(b)))


def runtime(abi: str, out: Path) -> None:
    arch = ABIS[abi][0]
    pk = {k: deb_files(fetch(*v)) for k, v in DEBS[arch].items()}
    proot = resolve(pk["proot"], PREFIX + "bin/proot")
    loader = resolve(pk["proot"], PREFIX + "libexec/proot/loader")
    talloc = resolve(pk["libtalloc"], PREFIX + "lib/libtalloc.so.2")
    shmem = resolve(pk["libandroid-shmem"], PREFIX + "lib/libandroid-shmem.so")
    proot = rename_needed(proot, "libtalloc.so.2", "libtalloc.so")
    talloc = rename_needed(talloc, "libtalloc.so.2", "libtalloc.so")
    for name, b in [("libproot.so", proot), ("libproot_loader.so", loader), ("libtalloc.so", talloc),
                    ("libandroid-shmem.so", shmem)]:
        (out / name).write_bytes(b)
        os.chmod(out / name, 0o755)


def lookd(abi: str, out: Path, version: str) -> None:
    env = dict(os.environ, GOOS="linux", GOARCH=ABIS[abi][1], CGO_ENABLED="0")
    # timetzdata: ubuntu-base has no /usr/share/zoneinfo, and the app
    # passes the phone's zone as TZ.
    subprocess.run(["go", "build", "-trimpath", "-tags", "timetzdata", "-ldflags",
                    f"-s -w -X lookstudio/lookd/internal/server.Version={version}",
                    "-o", str(out / "liblookd.so"), "./cmd/lookd"], cwd=REPO / "lookd", env=env, check=True)


def agent() -> None:
    """The agent's sources and lockfile; dependencies install on device."""
    dest = MAIN / "assets" / "look"
    dest.mkdir(parents=True, exist_ok=True)
    src = REPO / "agent"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", compresslevel=9) as t:
        for rel in ["package.json", "package-lock.json", "src", "plugins"]:
            p = src / rel
            if p.exists():
                t.add(p, arcname=rel, filter=lambda m: None if m.name.endswith(".test.mjs") or "/node_modules" in m.name else m)
    # Not .tar.gz: the APK packager unpacks and renames assets ending in .gz.
    (dest / "agent.tgz").write_bytes(buf.getvalue())
    (dest / "agent.sha256").write_text(hashlib.sha256(buf.getvalue()).hexdigest())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--abi", default="arm64-v8a,x86_64")
    ap.add_argument("--version", default="0.1.0")
    ap.add_argument("--skip-lookd", action="store_true")
    ap.add_argument("--skip-agent", action="store_true")
    a = ap.parse_args()
    for abi in a.abi.split(","):
        if abi not in ABIS:
            sys.exit(f"unsupported ABI {abi}")
        out = MAIN / "jniLibs" / abi
        out.mkdir(parents=True, exist_ok=True)
        runtime(abi, out)
        if not a.skip_lookd:
            lookd(abi, out, a.version)
        print(f"{abi}: " + ", ".join(f"{f.name} {f.stat().st_size // 1024} KB" for f in sorted(out.iterdir())))
    if not a.skip_agent:
        agent()
        print(f"agent: {(MAIN / 'assets' / 'look' / 'agent.tgz').stat().st_size // 1024} KB")
    # proot and talloc are (L)GPL; their notice ships inside the APK.
    (MAIN / "assets" / "look").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(HERE / "NOTICE", MAIN / "assets" / "look" / "NOTICE")


if __name__ == "__main__":
    main()
