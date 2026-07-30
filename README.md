# camelot-gcc

Vendored, patched GCC source that reproduces Camelot's GBA-era codegen
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

The first two reproduce **Camelot's own** code. `old_agbcc` is different in
kind; it reproduces the **prebuilt stock m4a ("Sappy") audio engine** that
GS1 links verbatim. See [agbcc](#agbcc-stock-m4a--sappy).

## Build & install

```sh
sudo apt install -y build-essential           # + binutils-arm-none-eabi (for agbcc)
./build.sh all                                # or: gcc3 | agbcc | all
./install.sh <YOUR-GOLDENSUN-DECOMP> all      # same token
```

- The vendored trees ship pre-generated `configure` / `c-parse.c` / `c-gperf.h`,
  timestamp-pinned newer than their inputs, so `autoconf` / `bison` / `m4` /
  `gperf` are never invoked and need not be installed.
- agbcc builds `-j1` (its 2.9-era genfiles tree isn't parallel-safe).
- All `tools/<token>/` install dirs are gitignored in the decomp.

## Validation

- **gcc-2.96** reproduces the full Golden Sun ROM byte-identically (SHA1
  `5c4695205413df7db52b9a184815a07783999971`) against the goldensun Makefile
  flag set. Supported, regression-tested path.
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

- **gcc-2.96 (10):** refreshed `config.sub`/`config.guess`; x86_64 host entry in
  `configure`; `collect2.c` `open(...,0666)`; touch `c-parse.c` newer than `.y`
  (modern bison rejects the `.y`); `c-gperf.h` `is_reserved_word` → `static`;
  **`config/arm/elf.h` `ASM_OUTPUT_ALIGN` → `.align N, 0`** (zero-fill pad);
  and Darwin/Apple-Silicon host compatibility for libiberty symbols, i386
  host-header assumptions, and generated instruction-builder calls.
- **gcc-3.0 (5):** `config.sub`/`config.guess`; x86_64 in `config.gcc`;
  `arm.c` `DECL_RTL(sym)=new` → `SET_DECL_RTL(sym,new)`; `collect2.c`
  `open(...,0666)`; the same **`elf.h` zero-fill** patch.

Only the `elf.h` `.align N, 0` patch affects codegen (modern `arm-none-eabi-as`
pads with Thumb nops; Camelot's binutils padded with zeros). Both gcc trees are
pruned to a C-only cross-compiler (~37 MB each, from ~89/105 MB upstream).

## Compile flags (goldensun Makefile)

```
-O2 -mthumb -mthumb-interwork -mcpu=arm7tdmi -fno-builtin -nostdinc -ffreestanding -fcall-used-r4
```

`-fcall-used-r4` marks r4 caller-clobbered (Camelot's ABI). gcc-3.0 additionally
needs `-ffixed-r7`; gcc-2.96 avoids r7 naturally.

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
</content>
