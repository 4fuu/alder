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
link_cflags=${BOOTSTRAP_CFLAGS-"-O2"}
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
        *"__GNUC__"*)
            # Part-only suppression, never applied to the host shim or the
            # runtime: gcc's jump threading reports the tag-guarded payload
            # reads of one aggregate local (through offsetof) in the
            # generated parse_array_literal as definitely uninitialized.
            # That is the plain -Wuninitialized diagnostic class, which
            # -Wno-maybe-uninitialized does not cover. The suppression is
            # sound because MIR phase verification already proves definite
            # initialization of the generated code, so the warning
            # duplicates a check the verifier owns; single-TU compiles of
            # the pinned artifact (go test ./compiler, -O0) stay clean
            # under the full strict set.
            bootstrap_cflags="$bootstrap_cflags -Wno-maybe-uninitialized"
            bootstrap_cflags="$bootstrap_cflags -Wno-uninitialized"
            ;;
    esac
fi
case $(uname -s) in
    Linux) host_flags=-DALDER_HOST_LARGE_STACK ;;
    MINGW*|MSYS*) bootstrap_ldflags="$bootstrap_ldflags -Wl,--stack,33554432" ;;
esac

# Opt-in stage-0 cache. The key covers every input of the committed compiler
# build: the three C sources, the whole flag set, the host compiler identity,
# and this script's own bytes (the stage-0 splitter lives here), so a changed
# source, flag, toolchain, or splitter always misses. An entry replaces only
# the C compile; the regeneration and the byte-for-byte comparison below
# always run, and every failure falls back to a full build.
alder_bin=$tmp/alder
if [ "$cache" = true ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        cc_version=$("$cc" -dumpfullversion 2>/dev/null ||
            "$cc" -dumpversion 2>/dev/null || echo unknown)
        cc_machine=$("$cc" -dumpmachine 2>/dev/null || echo unknown)
        cc_path=$(command -v "$cc" 2>/dev/null || echo "$cc")
        script_digest=$(sha256sum "$script_dir/regenerate.sh")
        script_digest=${script_digest%% *}
        cache_key=$(
            printf 'cc=%s\nversion=%s\nmachine=%s\nstrict=%s\ncflags=%s\nlinkflags=%s\nhost=%s\nldflags=%s\nincludes=%s\nscript=%s\n' \
                "$cc_path" "$cc_version" "$cc_machine" \
                "$strict" "$bootstrap_cflags" "$link_cflags" "$host_flags" "$bootstrap_ldflags" \
                '-I runtime/c -I bootstrap' \
                "$script_digest"
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
    # The stage-0 build splits the generated compiler into four fixed
    # translation units compiled in parallel: gcc's cost on one ~25 MB unit
    # dominates the cold bootstrap, and four concurrent -O2 compiles cut that
    # stage roughly fourfold on a four-CPU host. bootstrap/alder.c stays the
    # single pinned artifact; the split exists only inside this temporary
    # build tree. The splitter is POSIX awk, reads the file twice (plan, then
    # write), validates the generated shape it relies on, and fails loudly
    # instead of producing a silently wrong split. The part count is fixed so
    # the split is identical on every host; parallelism is plain &/wait.
    split_dir=$tmp/alder-split
    mkdir -p "$split_dir"
    awk '
        function fail(msg) {
            print "bootstrap: splitter: " msg > "/dev/stderr"
            failed = 1
            exit 1
        }
        {
            line = $0
            lastc = substr(line, length(line))
            cls = "other"
            if (!in_inline) {
                if (line ~ /^static inline ALDER_MAYBE_UNUSED /) {
                    if (lastc == "{") cls = "idef"
                    else if (lastc == ";") cls = "iproto"
                    else fail("unclassified static inline line " NR)
                } else if (line ~ /^static ALDER_MAYBE_UNUSED /) {
                    if (line ~ /alder_fn_[A-Za-z0-9_]+\(/) {
                        if (lastc == "{") cls = "fdef"
                        else if (lastc == ";") cls = "fproto"
                        else fail("unclassified function line " NR)
                    } else if (lastc == ";") {
                        cls = "data"
                    } else {
                        fail("unclassified static line " NR ": " line)
                    }
                } else if (line ~ /^static /) {
                    fail("unexpected static-prefixed line " NR ": " line)
                } else if (line ~ /^int32_t alder_program_entry/) {
                    cls = "entry"
                }
            }
            if (cls == "entry" && entry)
                fail("duplicate program entry at " NR " and " entry)
            if (hdr_end) cum++
            if (in_inline) {
                if (substr(line, 1, 1) == "}") in_inline = 0
                next
            }
            if (cls == "idef") {
                in_inline = 1
                last_inline = NR
                if (!hdr_end) hdr_end = NR
            } else if (cls == "fdef") {
                if (!hdr_end) hdr_end = NR
                ndefs++
                defnr[ndefs] = NR
                defcum[ndefs] = cum
            } else if (cls == "entry") {
                entry = NR
                cum_entry = cum - 1
            } else if (cls == "data" && hdr_end) {
                fail("data definition after first function definition at line " NR)
            }
        }
        END {
            if (failed) exit 1
            if (!hdr_end) fail("no function definition found")
            if (!entry) fail("no program entry found")
            if (entry <= defnr[ndefs])
                fail("program entry is not after the last function definition")
            if (in_inline)
                fail("unterminated static-inline block starting at line " last_inline)
            if (ndefs < 4) fail("too few function definitions to split")
            if (cum_entry <= 0)
                fail("no function body lines between header and entry")
            thresh[1] = int(cum_entry / 4)
            thresh[2] = int(cum_entry / 2)
            thresh[3] = int(cum_entry * 3 / 4)
            j = 1
            for (i = 1; i <= ndefs; i++) {
                while (j <= 3 && defcum[i] >= thresh[j]) {
                    cutnr[j] = defnr[i]
                    j++
                }
            }
            if (j <= 3) fail("could not place three cut points")
            if (cutnr[1] <= hdr_end || cutnr[1] >= cutnr[2] ||
                cutnr[2] >= cutnr[3] || cutnr[3] >= entry)
                fail("cut points are not strictly ordered")
            print hdr_end, cutnr[1], cutnr[2], cutnr[3], entry
        }
    ' bootstrap/alder.c > "$tmp/split-plan.txt"
    read -r hdr_end cut1 cut2 cut3 entry rest < "$tmp/split-plan.txt"
    for number in "$hdr_end" "$cut1" "$cut2" "$cut3" "$entry"; do
        case $number in
            ''|*[!0-9]*)
                echo "bootstrap: splitter produced an invalid plan" >&2
                exit 1
                ;;
        esac
    done
    [ -z "$rest" ] || {
        echo "bootstrap: splitter produced an invalid plan" >&2
        exit 1
    }
    awk -v hdr_end="$hdr_end" -v cut1="$cut1" -v cut2="$cut2" \
        -v cut3="$cut3" -v entry="$entry" \
        -v h="$split_dir/alder_split.h" \
        -v ih="$split_dir/alder_split_inline.h" \
        -v p0="$split_dir/part0.c" -v p1="$split_dir/part1.c" \
        -v p2="$split_dir/part2.c" -v p3="$split_dir/part3.c" '
        BEGIN {
            print "#include \"alder_split.h\"" > p0
            print "#include \"alder_split_inline.h\"" > p0
            print "#include \"alder_split.h\"" > p1
            print "#include \"alder_split_inline.h\"" > p1
            print "#include \"alder_split.h\"" > p2
            print "#include \"alder_split_inline.h\"" > p2
            print "#include \"alder_split.h\"" > p3
            print "#include \"alder_split_inline.h\"" > p3
        }
        function fail(msg) {
            print "bootstrap: splitter: " msg > "/dev/stderr"
            failed = 1
            exit 1
        }
        function external(line,   t) {
            if (line ~ /^static ALDER_MAYBE_UNUSED / &&
                line ~ /alder_fn_[A-Za-z0-9_]+\(/) {
                t = substr(line, length(line))
                if (t == ";" || t == "{") sub(/^static /, "", line)
            }
            return line
        }
        {
            lastc = substr($0, length($0))
            if (in_inline) {
                print $0 > ih
                ih_lines++
                if (substr($0, 1, 1) == "}") in_inline = 0
                next
            }
            if ($0 ~ /^static inline ALDER_MAYBE_UNUSED / && lastc == "{") {
                print $0 > ih
                ih_lines++
                in_inline = 1
                next
            }
            if (NR < hdr_end) {
                print external($0) > h
                hdr_lines++
                next
            }
            if (NR >= entry) {
                print $0 > p3
                p3n++
                next
            }
            if (NR < cut1) {
                print external($0) > p0
                p0n++
            } else if (NR < cut2) {
                print external($0) > p1
                p1n++
            } else if (NR < cut3) {
                print external($0) > p2
                p2n++
            } else {
                print external($0) > p3
                p3n++
            }
        }
        END {
            if (failed) exit 1
            if (in_inline) fail("unterminated static-inline block")
            total = hdr_lines + ih_lines + p0n + p1n + p2n + p3n
            if (total != NR) fail("wrote " total " of " NR " lines")
            if (p0n == 0 || p1n == 0 || p2n == 0 || p3n == 0) fail("empty part")
        }
    ' bootstrap/alder.c
    for unit in alder_split.h alder_split_inline.h part0.c part1.c part2.c part3.c; do
        [ -s "$split_dir/$unit" ] || {
            echo "bootstrap: splitter did not produce $unit" >&2
            exit 1
        }
    done
    part_pids=
    for i in 0 1 2 3; do
        "$cc" $strict $bootstrap_cflags $host_flags \
            -I "$split_dir" -I runtime/c -I bootstrap \
            -c "$split_dir/part$i.c" -o "$split_dir/part$i.o" &
        part_pids="$part_pids $!"
    done
    stage0_status=0
    for pid in $part_pids; do
        wait "$pid" || stage0_status=1
    done
    [ "$stage0_status" -eq 0 ] || {
        echo "bootstrap: stage-0 unit compile failed" >&2
        exit 1
    }
    # The host shim and the runtime keep the full strict warning set; only
    # the four generated parts carry the part-only suppressions above.
    "$cc" $strict $link_cflags $host_flags \
        -I runtime/c -I bootstrap \
        bootstrap/alder_host.c runtime/c/alder.c \
        "$split_dir"/part0.o "$split_dir"/part1.o \
        "$split_dir"/part2.o "$split_dir"/part3.o \
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
