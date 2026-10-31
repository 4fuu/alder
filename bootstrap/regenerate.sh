#!/bin/sh
set -eu

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--write" ]; }; then
    echo "usage: bootstrap/regenerate.sh [--write]" >&2
    exit 2
fi
write=false
if [ "$#" -eq 1 ]; then
    write=true
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
root=$(dirname "$script_dir")
cd "$root"
export LC_ALL=C

cc=${CC:-cc}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/alder-bootstrap.XXXXXX")
trap 'rm -rf "$tmp"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

strict='-std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion'
bootstrap_cflags=${BOOTSTRAP_CFLAGS-"-O2"}
bootstrap_ldflags=${BOOTSTRAP_LDFLAGS:-}
host_flags=
cache=false
if [ "${ALDER_BOOTSTRAP_CACHE:-}" = "1" ]; then
    cache=true
fi
cache_dir=$root/.alder-cache
cache_key=
cache_file=

# The inventory verifier build is the only long stage that can overlap a
# check, so it starts first and the cheap checks finish while it compiles.
"$cc" $strict bootstrap/inventory_verify.c -o "$tmp/alder-inventory-verify" &
inventory_build=$!

if [ -z "${BOOTSTRAP_CFLAGS+x}" ]; then
    compiler_macros=$("$cc" -dM -E - </dev/null)
    case "$compiler_macros" in
        *"__clang__"*) ;;
        *"__GNUC__"*) bootstrap_cflags="$bootstrap_cflags -Wno-maybe-uninitialized" ;;
    esac
fi
case $(uname -s) in
    Linux) host_flags=-DALDER_HOST_LARGE_STACK ;;
    MINGW*|MSYS*) bootstrap_ldflags="$bootstrap_ldflags -Wl,--stack,33554432" ;;
esac

# Opt-in stage-0 cache. The key covers every input of the committed compiler
# build: the three C sources, the whole flag set, and the host compiler
# identity, so a changed source, flag, or toolchain always misses. An entry
# replaces only the C compile; the regeneration and the byte-for-byte
# comparison below always run, and every failure falls back to a full build.
alder_bin=$tmp/alder
if [ "$cache" = true ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        cc_version=$("$cc" -dumpfullversion 2>/dev/null ||
            "$cc" -dumpversion 2>/dev/null || echo unknown)
        cc_machine=$("$cc" -dumpmachine 2>/dev/null || echo unknown)
        cc_path=$(command -v "$cc" 2>/dev/null || echo "$cc")
        cache_key=$(
            printf 'cc=%s\nversion=%s\nmachine=%s\nstrict=%s\ncflags=%s\nhost=%s\nldflags=%s\nincludes=%s\n' \
                "$cc_path" "$cc_version" "$cc_machine" \
                "$strict" "$bootstrap_cflags" "$host_flags" "$bootstrap_ldflags" \
                '-I runtime/c -I bootstrap'
            sha256sum bootstrap/alder.c bootstrap/alder_host.c runtime/c/alder.c
        )
        cache_key=$(printf '%s\n' "$cache_key" | sha256sum)
        cache_key=${cache_key%% *}
        cache_file=$cache_dir/alder-stage0-$cache_key
        if [ -s "$cache_file" ] && [ -x "$cache_file" ]; then
            alder_bin=$cache_file
            echo "bootstrap: reused stage-0 cache $cache_key" >&2
        fi
    else
        echo "bootstrap: stage-0 cache needs sha256sum; building without it" >&2
    fi
fi

awk '
    NR == FNR {
        if (NR > 1 && $1 != "sha256") { inventory[$3] = 1; inventory_count++ }
        next
    }
    FNR == 1 { if ($0 != "ALDER-COMPILER-ORDER 1") exit 1; next }
    !($0 in inventory) || seen[$0] { exit 1 }
    { seen[$0] = 1; order_count++ }
    END { if (inventory_count != order_count) exit 1 }
' bootstrap/compiler-sources.manifest bootstrap/compiler-sources.order || {
    kill "$inventory_build" 2>/dev/null || true
    wait "$inventory_build" 2>/dev/null || true
    echo "bootstrap: compiler source order is not covered by the inventory" >&2
    exit 1
}

wait "$inventory_build"
"$tmp/alder-inventory-verify" bootstrap/compiler-sources.manifest .

if [ "$alder_bin" = "$tmp/alder" ]; then
    "$cc" $strict $bootstrap_cflags $host_flags \
        -I runtime/c -I bootstrap \
        bootstrap/alder.c bootstrap/alder_host.c runtime/c/alder.c \
        $bootstrap_ldflags -o "$tmp/alder"
    if [ "$cache" = true ] && [ -n "$cache_file" ]; then
        if mkdir -p "$cache_dir" &&
            mv -f "$tmp/alder" "$cache_dir/alder-stage0-$cache_key.partial" &&
            mv -f "$cache_dir/alder-stage0-$cache_key.partial" "$cache_file"; then
            alder_bin=$cache_file
            echo "bootstrap: stored stage-0 cache $cache_key" >&2
        fi
    fi
fi

set --
while IFS= read -r source; do
    if [ "$source" = "ALDER-COMPILER-ORDER 1" ]; then
        continue
    fi
    set -- "$@" "$source"
done < bootstrap/compiler-sources.order

# The private bootstrap profile carries the self-compile: compiler/src still
# uses the S0 bridges. The stage-0 binary links this tree's host shim, which
# owns argv, so a stage-0 compiler that predates the flag simply never queries
# it and the transition needs no special case here.
"$alder_bin" compile --emit=c --bootstrap-private "$@" > "$tmp/alder.c"
different=false
if ! cmp -s bootstrap/alder.c "$tmp/alder.c"; then
    different=true
    if [ "$write" = false ]; then
        echo "bootstrap: regenerated compiler differs from bootstrap/alder.c" >&2
        exit 1
    fi
fi

if [ "$write" = true ] && [ "$different" = true ]; then
    mv "$tmp/alder.c" bootstrap/alder.c
    echo "bootstrap: updated bootstrap/alder.c"
else
    echo "bootstrap: fixed point unchanged"
fi
