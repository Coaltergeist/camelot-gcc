# GCC 2.96 compatibility smoke corpus

These small, self-contained C fixtures need no game ROM, game headers, downloaded
reference checkout, or assembler to run. They exercise symbol references and
external calls, conditional labels and loops, narrow loads, multiplication,
literal pools, the r4 ABI, and padding between adjacent functions. The expected
files are exact compiler assembly, including relocation-bearing symbol operands
and alignment directives. The game build's final appended alignment is outside
this compiler-only test.

The three `tests/expected/*.s` files are intentionally checked-in test baselines.
Commit them with the fixtures and provenance; they are not disposable build outputs
and must not be added to `.gitignore`.

```sh
set -o pipefail
./build.sh gcc296 2>&1 | tee output.txt
python3 tests/run.py 2>&1 | tee -a output.txt
```

The runner defaults to `build-296/gcc`. Use `--compiler-dir /path/to/tools/gcc296`
to test an installed compiler. Every fixture runs in three separate compiler
processes by default (`--repeats N`). Differences fail; the runner never updates
expected results. Local scratch outputs live under ignored `test-work/`.

## Recorded baseline

Captured on 2026-09-09 from the production compiler installed for game revision
`55d2d328c1765620c75e39e934204dd7bbb24639`, paired with compiler repository revision
`0a34b38ff830ce80db98c9577c5a1e1d24fa74a7`. That pairing had passed a fresh serial full
Golden Sun USA ROM comparison and all 96 overlays before capture. The ROM SHA1 is
`5c4695205413df7db52b9a184815a07783999971`.

`provenance.json` records the fixture/output hashes, compile flags, installed
compiler hashes, host identity and compiler build-manifest hash. These snapshots
were captured from that compiler, not recovered from original Camelot objects.
They are useful compatibility expectations, not independent proof that these
newly written C examples reproduce unknown original source.

## Limits and changes

This is a small smoke corpus, not a reproducer known to fail for each historical
hashing patch. Repeated processes on one host do not establish cross-host
determinism; other hosts need separate results. Compiler changes still require
fresh full-game verification, including overlays and production per-file settings.
A compatible assembly snapshot also does not establish the semantics of a game's
existing fakematches. Golden Sun accepts no new fakematches and is removing the
legacy ones.

If output changes, investigate the instruction, symbol and padding differences.
Do not regenerate snapshots merely to make the test pass. Any intentional baseline
change needs reviewed reasoning, updated provenance, and full-game results for the
compiler/game pairing being proposed.
