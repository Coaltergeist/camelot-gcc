# camelot-gcc

Vendored, patched GCC source used to reproduce Golden Sun's GBA machine code
byte-identically, for the [goldensun decomp](https://github.com/Coaltergeist/goldensun-decomp)
(and in principle other Camelot GBA matching-decomps). Mirrors the
[pret/agbcc](https://github.com/pret/agbcc) shape: vendored source + a build
script + an install script that drops binaries into a sibling decomp checkout.

## Compilers

One `build.sh` / `install.sh` pair drives all three, dispatched by a token:

| Compiler | Vendored at | Token | Installs to | Role |
|---|---|---|---|---|
| **gcc-2.96 dev snapshot (2000-07-31)** | `gcc-2.96/` | `gcc296` | `tools/gcc296/` | **GS1 production** |
| gcc-3.0 release | `gcc-3.0/` | `gcc3` | `tools/gcc3/` | GS2 starting point (not wired in) |
| pret/agbcc `old_agbcc` | `agbcc/` (pruned) | `agbcc` | `tools/agbcc/` | stock m4a / "Sappy" engine |

GCC 2.96 is the validated GS1 game-code compiler. GCC 3.0 is a research
baseline, not a demonstrated GS2 reproduction. `old_agbcc` reproduces the
**prebuilt stock m4a ("Sappy") audio engine** and most Flash library C in GS1. See [agbcc](#agbcc-stock-m4a--sappy).

## Build & install

```sh
set -o pipefail
sudo apt install -y build-essential binutils-arm-none-eabi python3 git 2>&1 | tee output.txt
./build.sh all 2>&1 | tee -a output.txt
./install.sh <YOUR-GOLDENSUN-DECOMP> all 2>&1 | tee -a output.txt
```

- The vendored trees ship pre-generated `configure` / `c-parse.c` / `c-gperf.h`,
  timestamp-pinned newer than their inputs, so `autoconf` / `bison` / `m4` /
  `gperf` are not needed for the normal build. Regenerating those files is a
  separate development task and may require historical generator versions.
- agbcc builds `-j1` (its 2.9-era genfiles tree isn't parallel-safe).
- All `tools/<token>/` install dirs are gitignored in the decomp.

## Validation

- **gcc-2.96** reproduces the full Golden Sun ROM byte-identically (SHA1
  `5c4695205413df7db52b9a184815a07783999971`) against the goldensun Makefile
  flag set. See [tests/README.md](tests/README.md) for the recorded pairing and
  independent compatibility smoke corpus. Full-game equality includes remaining
  assembly and legacy fakematches; it does not certify all source semantics.
- **gcc-3.0** builds on modern hosts but isn't wired into the decomp; it can't
  reach fingerprint #5 natively. Kept as a clean GS2 baseline.
- **agbcc**: a leaf m4a function (`MidiKeyToFreq`) built with `old_agbcc` is
  byte-identical to its GS1 `rom_f9000` bytes (reloc-masked); gcc-2.96 diverged
  in 76/100 bytes.

## agbcc (stock m4a / "Sappy")

GS1's audio engine (`rom_f9000`) is the prebuilt MKS4AGB / "Sappy" library,
statically linked from the stock object every GBA licensee shipped (identical
to SA2's, modulo one `SOUND_MODE` constant). It only matches under `old_agbcc`,
not under gcc-2.96 (Camelot's `-fcall-used-r4` ABI).

Vendored as a **pruned** checkout of pret/agbcc @ `da598c1d918402c42c0c0d7128ba14567f3175e9`,
keeping only what builds `old_agbcc` (the Thumb cc1) + its install headers
(`gcc/`, `ginclude/`, `libc/include/`, `include/`). Dropped: the ARM cc1 tree
`gcc_arm/` (~19 MB, unused; GS1's m4a is all Thumb and links via the goldensun
linker), `libiberty/`, `libc/`'s C sources. 47 MB → ~8 MB. No source patches
needed (pret already ships modern-host flags in `agbcc/gcc/Makefile`).

## Patches to vendored source

`build.sh` restores exec bits and timestamp-pins generated files, and adds host
CFLAGS (`-std=gnu17` to dodge gcc-15's C23 default; `-fcommon` for gcc-2.96).
Source patches applied in-tree:

- **gcc-2.96 host compatibility:** refreshed `config.sub`/`config.guess`,
  x86_64 configure support, `collect2.c` file-creation mode, `c-gperf.h` linkage,
  and Darwin/Apple-Silicon compatibility changes. Build scripts preserve shipped
  generated files. These patches are not evidence that every host is validated.
- **gcc-2.96 optimizer compatibility:** `simplify-rtx.c:hash_rtx` hashes symbol
  names by content (commit `7d6f4af776a9ceeb7a70d95864b5d8112a383574`). Commit
  `87601c6997b2e95daaedfb6eeefe7e4e851a44bf` does the same in `cse.c:canon_hash`
  and changes label hashing in both functions to `CODE_LABEL_NUMBER`.
  The original cases used host pointer values. Bucket placement can affect
  optimizer choices, so these **can affect generated code**, not just host
  compilation. Their purpose is to remove these specific heap-layout inputs;
  they do not prove that every other optimization is host-independent.
- **Both GCC trees:** `config/arm/elf.h` emits `.align N, 0` to reproduce zero
  padding with modern assemblers. This also affects output bytes. The game
  build separately appends a final zero-filled alignment after each C TU.
- **gcc-3.0 host/source compatibility:** refreshed host configuration,
  `SET_DECL_RTL` use in `arm.c`, and `collect2.c` file-creation mode.

Both GCC trees are pruned to a C-only cross-compiler (~37 MB each, from
~89/105 MB upstream). The compatibility patch descriptions are not an assertion
that the compiler is an exact archival copy of Camelot's proprietary toolchain.

## Compile flags (goldensun Makefile)

```
-O2 -mthumb -mthumb-interwork -mcpu=arm7tdmi -fno-builtin -nostdinc -ffreestanding -fcall-used-r4 -fno-strict-aliasing
```

`-fcall-used-r4` marks r4 caller-clobbered (Camelot's ABI). gcc-3.0 additionally
needs `-ffixed-r7` for the studied GS1 fingerprints; GCC 2.96 uses the production
settings above. The game Makefile is authoritative: it also supplies include and
driver paths, omits interworking for the common2 TU, and selects different
compilers/flags for imported libraries.

## Camelot codegen fingerprints

| # | Pattern | Solved by |
|---|---|---|
| 1 | r4 caller-saved | `-fcall-used-r4` |
| 2 | Reverse `REG_ALLOC_ORDER` | inherent to gcc-2.95+ Thumb backend |
| 3 | Thumb instruction scheduling | inherent to gcc-2.95+ scheduler |
| 4 | Small-const literal-pool preference | `unsigned short` halfword target pools natively |
| 5 | MULT-by-non-pow2 → shift-add | gcc-2.96 cost model (3.0 can't reach) |
| 6 | `.align` pad = `0000` | `elf.h` patch |
| 7 | r7 reserved | `-ffixed-r7` (3.0) / inherent (2.96) |
| 8 | No STMIA merge on 3 stores | source-side: array indexing, not byte-ptr cast |
| 9 | Small-const word-pool in VFX subsystem | named absolute asset-symbols (`FILE_*`/`MSG_*` via linker `.sym`) |

## Scope

- **GS1 (2001):** byte-identical under gcc-2.96.
- **GS2 (2002):** Camelot used a GCC *fork* (BL→BLX inline, magic-number
  divide); patches not yet written; gcc-3.0 is the likely starting point.
- **Mario Tennis / Golf:** a newer Camelot fork (`.data` switch tables); out of
  scope.

## Credits

- **FutureFractal** — identified the GS1 compiler as stock GCC 3.0-era vs GS2's fork.
- **Tarpman** — 2021 thread documenting fingerprints #1–#5; #4 trigger repro.
- **Karathan** — published the working flag set on Compiler Explorer.
- The GBA decomp community for the pret/agbcc pattern this repo imitates.

## Build freshness and provenance

Run `./build.sh gcc296` after compiler changes. The GCC 2.96 and GCC 3.0
pipelines compare source contents, build-script contents, host compiler identity,
and flags with the previous configuration. Changed inputs start a fresh build;
previous build directories are retained under ignored `build-archive/`. Unchanged
inputs still run make rather than treating existing executables as proof of success.
Use `./build.sh gcc296 --rebuild` to explicitly start fresh. `NPROC` controls host
build parallelism; `HOST_CFLAGS_BASE`, `HOST_CXXFLAGS`, and `HOST_LDFLAGS` can be
overridden and are recorded in the input manifest.

A successful GCC build writes `build-manifest.json` with source hashes, revision,
dirty-state indication, host compiler/flags, and artifact SHA256 values. Installation
verifies that the sources and artifacts still match and copies the manifest with
the binaries. An old build without a manifest must be rebuilt before installation.
This records local provenance; it does not establish cross-host reproducibility.
The old_agbcc lane continues to clean and rebuild on each invocation; it does not
yet use the GCC build-manifest format.

Component attribution and notice locations: [ATTRIBUTION.md](ATTRIBUTION.md).

## Repository checks

The workflow builds GCC 2.96, verifies its build manifest and compares the independent compiler fixtures.
The GitHub workflow uses Ubuntu 22.04 and requires no game ROM or repository
secrets. A successful run does not certify game byte matching or source semantics.
Full-game contributions still require the fresh serial ROM/all-overlay gate and
source review. New fakematches are not accepted.
