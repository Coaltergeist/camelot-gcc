#!/usr/bin/env python3
"""Build input invalidation and verifiable compiler provenance (Python 3)."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sources(source):
    # The GCC trees build out of tree. Content hashing also catches edits with
    # preserved or older mtimes, which historical make dependency lists miss.
    paths = list(Path(source).rglob("*")) + [ROOT / "build.sh", ROOT / "build_manifest.py"]
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths) if p.is_file()}


def command_version(command):
    import shlex
    argv = shlex.split(command)
    executable = shutil.which(argv[0])
    if executable is None:
        raise ValueError("host compiler missing: " + command)
    return {"command": command, "executable_sha256": sha(executable),
            "version": subprocess.check_output(argv + ["--version"], text=True).splitlines()[0]}


def write_json(path, value):
    path = Path(path)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def prepare(source, build, target, cflags, cxxflags, ldflags, rebuild=False):
    source, build = Path(source).resolve(), Path(build)
    if build.is_symlink() or build.parent.resolve() != ROOT or build.name not in ("build", "build-296"):
        raise ValueError("build directory must be the repository's build or build-296 directory")
    inputs = dict(source=str(source.relative_to(ROOT)), sources=sources(source),
                  target=target, cflags=cflags, cxxflags=cxxflags, ldflags=ldflags,
                  host=platform.platform(), cc=command_version(os.environ.get("CC", "gcc")),
                  cxx=command_version(os.environ.get("CXX", "g++")),
                  configure_environment={k: os.environ.get(k) for k in
                      ("libiberty_cv_var_sys_errlist", "libiberty_cv_var_sys_nerr")})
    state = build / "build-inputs.json"
    old = json.loads(state.read_text()) if state.exists() else None
    if build.exists() and (rebuild or old != inputs):
        archive = ROOT / "build-archive"
        archive.mkdir(exist_ok=True)
        slot = Path(tempfile.mkdtemp(prefix=build.name + "-", dir=archive))
        build.rename(slot / build.name)
        print("retained previous build:", slot / build.name)
    build.mkdir(exist_ok=True)
    write_json(build / "build-inputs.json", inputs)


def record(build, artifacts):
    build = Path(build)
    inputs = json.loads((build / "build-inputs.json").read_text())
    if inputs["sources"] != sources(ROOT / inputs["source"]):
        raise ValueError("compiler sources changed during build")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=ROOT))
    manifest = dict(schema=1, built_at=datetime.now(timezone.utc).isoformat(),
                    revision=revision, dirty=dirty, inputs=inputs,
                    artifacts={"gcc/" + a: sha(build / "gcc" / a) for a in artifacts})
    write_json(build / "build-manifest.json", manifest)


def verify(build):
    build = Path(build)
    manifest = json.loads((build / "build-manifest.json").read_text())
    if manifest["inputs"]["sources"] != sources(ROOT / manifest["inputs"]["source"]):
        raise ValueError("source/build script changed after compilation; run build.sh first")
    for name, digest in manifest["artifacts"].items():
        if sha(build / name) != digest:
            raise ValueError("built artifact changed: " + name)
    print("compiler manifest verified:", build)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="mode", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("source"); prep.add_argument("build"); prep.add_argument("target")
    prep.add_argument("--cflags", required=True); prep.add_argument("--cxxflags", required=True)
    prep.add_argument("--ldflags", required=True); prep.add_argument("--rebuild", action="store_true")
    rec = sub.add_parser("record")
    rec.add_argument("build"); rec.add_argument("artifacts", nargs="+")
    ver = sub.add_parser("verify"); ver.add_argument("build")
    args = ap.parse_args()
    try:
        if args.mode == "prepare":
            prepare(args.source, args.build, args.target, args.cflags, args.cxxflags, args.ldflags, args.rebuild)
        elif args.mode == "record":
            record(args.build, args.artifacts)
        else:
            verify(args.build)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("compiler provenance: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
