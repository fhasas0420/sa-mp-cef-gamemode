#!/usr/bin/env bash
# =====================================================================
#  Build the samp-cef open.mp component (cef.so) for the pinned commit
#  and install it into omp-server/components/. Sources go to a temp dir
#  and are deleted afterwards.
#
#  Needs: rustup/cargo, cmake, ninja-build, gcc-multilib, g++-multilib
#    sudo apt install -y cmake ninja-build gcc-multilib g++-multilib
#    curl https://sh.rustup.rs -sSf | sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

OMP_VERSION="${OMP_VERSION:-v1.6.7.3218}"
CEF_COMMIT="$(cat "$ROOT/cef-version.txt")"
CEF_COMMIT="${CEF_COMMIT//[$'\r\n ']/}"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

for tool in git cargo rustup cmake ninja g++; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool (see header of this script)"; exit 1; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Work dir: $work"

# samp-cef at the exact pinned commit
git -C "$work" init -q samp-cef
git -C "$work/samp-cef" fetch -q --depth 1 https://github.com/ZOTTCE/samp-cef.git "$CEF_COMMIT"
git -C "$work/samp-cef" checkout -q FETCH_HEAD

# open.mp SDK matching the server version
git clone -q --depth 1 --branch "$OMP_VERSION" --recurse-submodules --shallow-submodules \
  https://github.com/openmultiplayer/open.mp.git "$work/open.mp"

rustup target add i686-unknown-linux-gnu >/dev/null

cd "$work/samp-cef"
cmake -S openmp-component/component -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DOPEN_MP_ROOT="$work/open.mp" -DSAMP_CEF_ENABLE_GRPC_EXT=OFF \
  -DSAMP_CEF_RUST_TARGET=i686-unknown-linux-gnu \
  -DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32 -DCMAKE_SHARED_LINKER_FLAGS=-m32 >/dev/null
cmake --build build --target cef 2>&1 | grep -E "error|Finished|Linking" || true
[[ -f build/cef.so ]] || { echo "BUILD FAILED"; exit 1; }

mkdir -p "$ROOT/omp-server/components"
# write next to the target, then rename: a running server keeps its old copy mapped
strip -s build/cef.so -o "$ROOT/omp-server/components/cef.so.new"
mv -f "$ROOT/omp-server/components/cef.so.new" "$ROOT/omp-server/components/cef.so"
file "$ROOT/omp-server/components/cef.so"
echo "Installed cef.so (samp-cef ${CEF_COMMIT:0:7}). Restart: ./server.sh restart"
