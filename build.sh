#!/usr/bin/env bash
# Build one (or all) of the three vendored compilers this repo ships.
#
#   ./build.sh gcc296   gcc-2.96 dev snapshot -> build-296/gcc/{cc1,xgcc,cpp,tradcpp}
#   ./build.sh gcc3     gcc-3.0 release       -> build/gcc/{cc1,xgcc,cpp0,tradcpp0}
#   ./build.sh agbcc    pret/agbcc old_agbcc  -> agbcc/gcc/old_agbcc
#   ./build.sh all      all three
#
# Then deploy with: ./install.sh path/to/goldensun-decomp <same target>
#
# Pre-reqs (Debian/Ubuntu): build-essential (+ binutils-arm-none-eabi, needed
# by agbcc). Host: tested on Ubuntu 22.04 + gcc-11 via WSL2.

set -e

cd "$(dirname "$0")"
HERE="$PWD"
NPROC="$(nproc 2>/dev/null || echo 4)"

# Host flags shared by the gcc-2.96 / gcc-3.0 trees. gcc-11+ emits warnings
# the 2000/2001-era source treats as errors without these silencers; -no-pie
# is required because that build infra produces non-PIE executables;
# -std=gnu17 pins the standard back from gcc-15's C23 default (which turns
# implicit-int / K&R declarations into hard errors the -Wno-* can't silence).
HOST_CFLAGS_BASE="-O2 -fno-pie -no-pie -Wno-narrowing -Wno-implicit-int -Wno-implicit-function-declaration -Wno-pointer-arith -Wno-int-conversion -Wno-format -Wno-error -std=gnu17 -Wno-incompatible-pointer-types"
HOST_CXXFLAGS="-O2 -fno-pie -no-pie -Wno-narrowing -Wno-error -std=gnu++17"
HOST_LDFLAGS="-no-pie"

# ---------------------------------------------------------------------------
# Build a gcc-2.96 / gcc-3.0 style C-only arm cross cc1 from a vendored tree.
#   $1 SRC          vendored source dir
#   $2 BUILD        out-of-tree build dir
#   $3 TARGET       target triple (arm-elf / arm-agb-elf)
#   $4 EXTRA_CFLAGS host CFLAGS delta (gcc-2.96 needs -fcommon; 3.0 does not)
#   $5 CPP          cpp artifact name   (cpp / cpp0)
#   $6 TRADCPP      tradcpp artifact name (tradcpp / tradcpp0)
# ---------------------------------------------------------------------------
build_gcc_tree() {
  local SRC="$1" BUILD="$2" TARGET="$3" EXTRA="$4" CPP="$5" TRADCPP="$6"
  local CF="$HOST_CFLAGS_BASE${EXTRA:+ $EXTRA}"

  [ -d "$SRC" ] || { echo "error: $SRC not found"; exit 2; }

  # Some configure / install helpers lose +x via Windows-side editing /
  # archive extraction. Restore them defensively.
  find "$SRC" \( -name configure -o -name config.sub -o -name config.guess \
                -o -name install-sh -o -name mkinstalldirs -o -name move-if-change \
                -o -name missing -o -name ltconfig -o -name ltmain.sh \
                -o -name mkdep \) -exec chmod +x {} \;

  # Pin timestamps on pre-shipped generated files. git clone does not preserve
  # mtimes, so a checkout can leave generator inputs (configure.in, *.y,
  # *.gperf) newer than their shipped outputs, making make try to re-run
  # autoconf/bison/gperf against modern tools that reject the 2000/2001-era
  # inputs. Stamp the inputs OLD and the outputs NEW so they look up-to-date.
  find "$SRC" \( -name configure.in -o -name "*.y" -o -name "*.gperf" \
              -o -name acconfig.h \) -exec touch -t 200001010000 {} \;
  find "$SRC" \( -name configure -o -name "c-parse.c" -o -name "c-parse.h" \
              -o -name "c-gperf.h" -o -name "cstamp-h.in" -o -name "config.in" \
              -o -name "tradcif.c" \) -exec touch {} \;

  mkdir -p "$BUILD"
  cd "$BUILD"

  # Stage 1: top-level configure (produces the dispatch Makefile only).
  if [ ! -f Makefile ]; then
    echo "[1/4] top-level configure ($TARGET)"
    CFLAGS="$CF" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS" \
      "$SRC/configure" \
        --prefix="$BUILD/install" \
        --target="$TARGET" --with-cpu=arm7tdmi \
        --enable-multilib --enable-interwork --enable-languages=c \
        --without-headers --disable-shared --disable-threads \
        --disable-libstdc++-v3 --disable-nls --disable-win32-registry \
        || true   # top-level libiberty/gcc configure stub failures are expected
  fi

  # Stage 2: libiberty (configured + built manually).
  if [ ! -f libiberty/libiberty.a ]; then
    echo "[2/4] libiberty"
    rm -rf libiberty && mkdir libiberty && cd libiberty
    CFLAGS="$CF" LDFLAGS="$HOST_LDFLAGS" \
      "$SRC/libiberty/configure" \
        --srcdir="$SRC/libiberty" \
        --prefix="$BUILD/install" \
        --build=x86_64-unknown-linux-gnu --host=x86_64-unknown-linux-gnu \
        --target="$TARGET" --disable-shared --disable-nls
    make -j"$NPROC"
    cd ..
  fi

  # Stage 3: gcc/ subdir configure.
  if [ ! -f gcc/Makefile ]; then
    echo "[3/4] gcc/ configure"
    mkdir -p gcc && cd gcc
    CFLAGS="$CF" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS" \
      "$SRC/gcc/configure" \
        --srcdir="$SRC/gcc" \
        --prefix="$BUILD/install" \
        --build=x86_64-unknown-linux-gnu --host=x86_64-unknown-linux-gnu \
        --target="$TARGET" --with-cpu=arm7tdmi \
        --enable-multilib --enable-interwork --enable-languages=c \
        --without-headers --disable-shared --disable-threads --disable-nls \
        --with-gnu-as --with-gnu-ld
    cd ..
  fi

  # Stage 4: build the four host binaries directly from gcc/. We bypass the
  # top-level `all-gcc` umbrella (depends on configure.in regen rules we don't
  # ship) and fixinc (static-vs-extern collision with modern gcc, unneeded for
  # a freestanding cross-compile).
  if [ ! -x "gcc/cc1" ] || [ ! -x "gcc/xgcc" ] || [ ! -x "gcc/$CPP" ] || [ ! -x "gcc/$TRADCPP" ]; then
    echo "[4/4] make cc1 + xgcc + $CPP + $TRADCPP"
    cd gcc
    # Stamp config.status NEW so its --recheck rule (which re-runs configure's
    # compiler probe with flags lacking -std=gnu17) does not fire if
    # $SRC/gcc/configure has a fresher mtime after a re-clone.
    [ -f config.status ] && touch config.status
    # CFLAGS must be a command-line make variable, not an env var: gcc's
    # Makefile.in hard-codes CFLAGS = -O2 -g, and a Makefile internal
    # assignment beats inherited environment but not a command-line override.
    make -j"$NPROC" \
      CFLAGS="$CF" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS" \
      cc1 xgcc "$CPP" "$TRADCPP"
    cd ..
  fi

  echo
  if [ -x "gcc/cc1" ] && [ -x "gcc/xgcc" ] && [ -x "gcc/$CPP" ] && [ -x "gcc/$TRADCPP" ]; then
    echo "BUILD OK ($TARGET)"
    ls -la "gcc/cc1" "gcc/xgcc" "gcc/$CPP" "gcc/$TRADCPP"
  else
    echo "BUILD FAILED: artifacts missing in $BUILD/gcc/"
    ls -la gcc/ 2>&1 | head -20
    exit 1
  fi
  cd "$HERE"
}

# ---------------------------------------------------------------------------
# Build pret/agbcc's old_agbcc (the Thumb cc1 that reproduces the stock m4a /
# "Sappy" audio engine). Only old_agbcc is built and the vendored tree is
# pruned to it; see the "agbcc" section in README.md. No source patches are
# needed (pret ships the modern-host flags in agbcc/gcc/Makefile); the genfiles
# tree is not parallel-safe, so this is -j1.
# ---------------------------------------------------------------------------
build_agbcc() {
  local SRC="$HERE/agbcc"
  [ -d "$SRC/gcc" ] || { echo "error: $SRC/gcc not found (is agbcc vendored?)"; exit 2; }

  find "$SRC" \( -name configure -o -name config.sub -o -name config.guess \
                -o -name install-sh -o -name move-if-change -o -name mkdep \) \
       -exec chmod +x {} \; 2>/dev/null || true

  make -C "$SRC/gcc" clean
  make -C "$SRC/gcc" old -j1

  echo
  if [ -x "$SRC/gcc/old_agbcc" ]; then
    echo "BUILD OK (agbcc)"
    ls -la "$SRC/gcc/old_agbcc"
  else
    echo "BUILD FAILED: $SRC/gcc/old_agbcc missing"
    exit 1
  fi
}

build_296() {
  # Darwin still declares sys_errlist/sys_nerr, but no longer exports them.
  # Force gcc-2.96's libiberty fallback without leaking the cache settings
  # into the gcc-3.0 build when the selected target is "all".
  if [ "$(uname -s)" = "Darwin" ]; then
    local libiberty_cv_var_sys_errlist="${libiberty_cv_var_sys_errlist:-no}"
    local libiberty_cv_var_sys_nerr="${libiberty_cv_var_sys_nerr:-no}"
    export libiberty_cv_var_sys_errlist libiberty_cv_var_sys_nerr
  fi
  build_gcc_tree "$HERE/gcc-2.96" "$HERE/build-296" arm-elf "-fcommon" cpp tradcpp
}
build_gcc3() { build_gcc_tree "$HERE/gcc-3.0"  "$HERE/build"     arm-agb-elf ""         cpp0 tradcpp0; }

TARGET="${1:-}"
case "$TARGET" in
  gcc296) build_296 ;;
  gcc3)   build_gcc3 ;;
  agbcc)  build_agbcc ;;
  all)    build_296; echo; build_gcc3; echo; build_agbcc ;;
  *)
    echo "usage: $0 <gcc296|gcc3|agbcc|all>"
    echo "  gcc296  gcc-2.96 (GS1 production)   -> install dir tools/gcc296/"
    echo "  gcc3    gcc-3.0  (GS2 starting pt)  -> install dir tools/gcc3/"
    echo "  agbcc   old_agbcc (stock m4a/Sappy) -> install dir tools/agbcc/"
    echo "  all     all three"
    exit 2 ;;
esac

echo
echo "next: ./install.sh path/to/goldensun-decomp $TARGET"
