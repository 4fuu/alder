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

"$cc" $strict bootstrap/inventory_verify.c -o "$tmp/alder-inventory-verify"
"$tmp/alder-inventory-verify" bootstrap/compiler-sources.manifest .

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
    echo "bootstrap: compiler source order is not covered by the inventory" >&2
    exit 1
}

"$cc" $strict $bootstrap_cflags $host_flags \
    -I runtime/c -I bootstrap \
    bootstrap/alder.c bootstrap/alder_host.c runtime/c/alder.c \
    $bootstrap_ldflags -o "$tmp/alder"

set --
while IFS= read -r source; do
    if [ "$source" = "ALDER-COMPILER-ORDER 1" ]; then
        continue
    fi
    set -- "$@" "$source"
done < bootstrap/compiler-sources.order

"$tmp/alder" compile --emit=c "$@" > "$tmp/alder.c"
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
