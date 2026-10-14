#!/usr/bin/env bash
# Build official SourcePawn 1.12 + its VM without installing system packages.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_dir="$project_root/.toolchain"
mkdir -p "$toolchain_dir"

clone_pin() {
    local repository_url="$1" checkout_dir="$2" revision="$3"
    local fresh_checkout=0
    if [[ ! -d "$checkout_dir/.git" ]]; then
        git clone --no-checkout --depth 1 "$repository_url" "$checkout_dir"
        fresh_checkout=1
    fi
    if [[ "$(git -C "$checkout_dir" remote get-url origin)" != "$repository_url" ]]; then
        echo "Unexpected existing toolchain remote: $checkout_dir" >&2
        exit 1
    fi
    if [[ "$fresh_checkout" == 1 || "$(git -C "$checkout_dir" rev-parse HEAD)" != "$revision" ]]; then
        if [[ "$fresh_checkout" == 0 && -n "$(git -C "$checkout_dir" status --porcelain)" ]]; then
            echo "Preserve local toolchain changes before updating: $checkout_dir" >&2
            exit 1
        fi
        git -C "$checkout_dir" fetch --depth 1 origin "$revision"
        git -C "$checkout_dir" checkout --detach "$revision"
    fi
}

clone_pin https://github.com/alliedmodders/ambuild.git "$toolchain_dir/ambuild" 01212cb57c96561f664b6dfb2ee10e66de6f81e4
clone_pin https://github.com/alliedmodders/sourcemod.git "$toolchain_dir/sourcemod" 03865e00cc124221122ae9798ad38998566f9a2b
clone_pin https://github.com/alliedmodders/sourcepawn.git "$toolchain_dir/sourcepawn" 11b22edb634b9764d19fd28699e03289cfd18520
git -C "$toolchain_dir/sourcepawn" submodule update --init --recursive --depth 1

if [[ ! -x "$toolchain_dir/venv/bin/python" ]]; then
    python3 -m venv "$toolchain_dir/venv"
fi
"$toolchain_dir/venv/bin/python" -m pip install --disable-pip-version-check --no-cache-dir setuptools==80.10.2

mkdir -p "$toolchain_dir/build"
(
    cd "$toolchain_dir/build"
    # Upstream primarily targets Clang. GCC 14 also diagnoses fclose attributes,
    # signed shell indexes, and unused variables in upstream code.
    # Keep these warnings visible. A debug build retains upstream assertions.
    # The plugin itself is compiled with all warnings treated as errors.
    PYTHONPATH="$toolchain_dir/ambuild" CC=gcc CXX=g++ \
        CXXFLAGS='-Wno-error=ignored-attributes -Wno-error=sign-compare -Wno-error=unused-variable -Wno-error=unused-but-set-variable' \
        "$toolchain_dir/venv/bin/python" "$toolchain_dir/sourcepawn/configure.py" \
        --enable-debug --targets=x86_64
    if ! PYTHONPATH="$toolchain_dir/ambuild" "$toolchain_dir/venv/bin/python" \
        -c 'from ambuild2 import run; run.cli_run()' -j 4 > build.log 2>&1; then
        tail -60 build.log >&2
        exit 1
    fi
)

python3 "$project_root/tools/build.py" --sourcemod "$toolchain_dir/sourcemod" \
    --compiler "$toolchain_dir/build/spcomp/linux-x86_64/spcomp"
python3 "$project_root/tools/test.py"
