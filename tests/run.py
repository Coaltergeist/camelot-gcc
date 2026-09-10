#!/usr/bin/env python3
"""Compare GCC 2.96 output with reviewed assembly snapshots; never update them."""
import argparse
import difflib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"


def compile_fixture(compiler, fixture, output, flags):
    subprocess.run([str(compiler / "xgcc"), "-B" + str(compiler) + "/",
                    *flags, "-S", fixture.name, "-o", str(output)],
                   cwd=fixture.parent, check=True, timeout=60)
    return output.read_text()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--compiler-dir", type=Path, default=ROOT / "build-296/gcc")
    ap.add_argument("--repeats", type=int, default=3)
    args = ap.parse_args()
    if args.repeats < 1:
        ap.error("repeats must be positive")
    compiler = args.compiler_dir.resolve()
    contract = json.loads((TESTS / "provenance.json").read_text())
    work = ROOT / "test-work"
    work.mkdir(exist_ok=True)
    failed = False
    with tempfile.TemporaryDirectory(prefix="gcc296-", dir=work) as temp:
        for name in contract["fixtures"]:
            fixture = TESTS / "fixtures" / name
            expected = (TESTS / "expected" / fixture.with_suffix(".s").name).read_text()
            for attempt in range(args.repeats):
                actual = compile_fixture(compiler, fixture, Path(temp) / "actual.s", contract["flags"])
                if actual != expected:
                    failed = True
                    print("FAIL:", name, "run", attempt + 1)
                    print("".join(difflib.unified_diff(expected.splitlines(True),
                        actual.splitlines(True), fromfile="expected", tofile="actual")))
                    break
            else:
                print("PASS:", name, "(" + str(args.repeats) + " compiler processes)")
    return int(failed)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("compiler regression:", exc, file=sys.stderr)
        raise SystemExit(1)
