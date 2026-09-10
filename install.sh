#!/usr/bin/env bash
# Install one (or all) of the built compilers into a goldensun-decomp checkout.
# Run ./build.sh <target> first.
#
#   ./install.sh ../goldensun-decomp gcc296   -> tools/gcc296/  (cc1 xgcc cpp tradcpp)
#   ./install.sh ../goldensun-decomp gcc3     -> tools/gcc3/    (cc1 xgcc cpp0 tradcpp0)
#   ./install.sh ../goldensun-decomp agbcc    -> tools/agbcc/   (bin/old_agbcc + include/)
#   ./install.sh ../goldensun-decomp all      -> all three
#
# The goldensun Makefile finds these by default at GCC296_DIR ?= tools/gcc296
# (production) etc. All install dirs are gitignored in the decomp.

set -e

cd "$(dirname "$0")"
HERE="$PWD"

TARGET_DIR="${1:-}"
WHICH="${2:-}"
if [ -z "$TARGET_DIR" ] || [ -z "$WHICH" ]; then
  echo "usage: $0 path/to/goldensun-decomp <gcc296|gcc3|agbcc|all>"
  exit 2
fi
if [ ! -d "$TARGET_DIR" ]; then
  echo "error: target directory does not exist: $TARGET_DIR"
  exit 2
fi

# Copy gcc-2.96 / gcc-3.0 binaries from a build dir into tools/<name>/.
#   $1 BUILD dir   $2 install subdir name   $3.. artifact basenames
install_gcc_tree() {
  local BUILD="$1" NAME="$2"; shift 2
  local f DEST="$TARGET_DIR/tools/$NAME"
  for f in "$@"; do
    [ -x "$BUILD/gcc/$f" ] || { echo "error: $BUILD/gcc/$f missing. Run ./build.sh first."; exit 2; }
  done
  python3 "$HERE/build_manifest.py" verify "$BUILD"
  mkdir -p "$DEST"
  for f in "$@"; do cp "$BUILD/gcc/$f" "$DEST/"; chmod +x "$DEST/$f"; done
  cp "$BUILD/build-manifest.json" "$DEST/build-manifest.json"
  echo "installed $NAME binaries and build manifest into $DEST"
  ls -la "$DEST"
}

install_agbcc() {
  local SRC="$HERE/agbcc" DEST="$TARGET_DIR/tools/agbcc"
  [ -x "$SRC/gcc/old_agbcc" ] || { echo "error: $SRC/gcc/old_agbcc missing. Run ./build.sh agbcc first."; exit 2; }
  mkdir -p "$DEST/bin" "$DEST/include"
  cp "$SRC/gcc/old_agbcc" "$DEST/bin/"
  chmod +x "$DEST/bin/old_agbcc"
  # One include dir, exactly like pret: agbcc-aware libc headers (string.h,
  # stdio.h, sys/, machine/, ...) plus compiler headers (stddef.h, stdarg.h, ...).
  cp -R "$SRC/libc/include/." "$DEST/include/"
  cp -R "$SRC/ginclude/."     "$DEST/include/"
  echo "installed old_agbcc + headers into $DEST"
  ls -la "$DEST/bin"
  echo "include dir: $(ls "$DEST/include" | wc -l) entries"
}

install_296()  { install_gcc_tree "$HERE/build-296" gcc296 cc1 xgcc cpp  tradcpp;  }
install_gcc3() { install_gcc_tree "$HERE/build"     gcc3   cc1 xgcc cpp0 tradcpp0; }

case "$WHICH" in
  gcc296) install_296 ;;
  gcc3)   install_gcc3 ;;
  agbcc)  install_agbcc ;;
  all)    install_296; echo; install_gcc3; echo; install_agbcc ;;
  *)
    echo "usage: $0 path/to/goldensun-decomp <gcc296|gcc3|agbcc|all>"
    exit 2 ;;
esac
