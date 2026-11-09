# Split the generated compiler C into four parallel translation units.
#
# The generated compiler's shape is pinned by the C backend goldens: a
# declaration header, static inline definitions, static data declarations,
# then function prototypes and definitions, and finally the program entry.
# The splitter classifies each line, quarters the function-body lines with
# three cut points, and emits one shared header, one shared inline header,
# and four part files whose compiles can run in parallel. regenerate.sh uses
# it for the stage-0 build and the Go test harness uses it for its own
# builds of freshly generated compiler C, so the split is byte-identical
# everywhere and there is only one implementation. The part count is fixed
# so the split is identical on every host. Every unexpected shape fails
# loudly instead of producing a silently wrong split.
#
# Modes (POSIX awk):
#   awk -v mode=plan -f bootstrap/split-c.awk INPUT
#       Print one plan line: hdr_end cut1 cut2 cut3 entry.
#   awk -v mode=write -v split_dir=DIR -v hdr_end=N -v cut1=N -v cut2=N \
#       -v cut3=N -v entry=N -f bootstrap/split-c.awk INPUT
#       Write DIR/alder_split.h, DIR/alder_split_inline.h, and
#       DIR/part0.c .. DIR/part3.c.
#
# plan mode validates the shape and the cut-point ordering; write mode
# re-derives the inline blocks while writing and re-checks the ordering and
# the line totals, so a plan applied to a different file cannot pass
# silently.

function fail(msg) {
    print "bootstrap: splitter: " msg > "/dev/stderr"
    failed = 1
    exit 1
}

# external strips the internal linkage from generated function lines so a
# definition in one part satisfies references from the other parts; the
# header receives the same rewrite, so every part sees external
# declarations.
function external(line,   t) {
    if (line ~ /^static ALDER_MAYBE_UNUSED / &&
        line ~ /alder_fn_[A-Za-z0-9_]+\(/) {
        t = substr(line, length(line))
        if (t == ";" || t == "{") sub(/^static /, "", line)
    }
    return line
}

BEGIN {
    if (mode != "plan" && mode != "write")
        fail("mode must be plan or write")
    if (mode == "write") {
        if (split_dir == "")
            fail("write mode needs split_dir")
        if (hdr_end == "" || cut1 == "" || cut2 == "" || cut3 == "" || entry == "")
            fail("write mode needs hdr_end, cut1, cut2, cut3, and entry")
        h = split_dir "/alder_split.h"
        ih = split_dir "/alder_split_inline.h"
        p0 = split_dir "/part0.c"
        p1 = split_dir "/part1.c"
        p2 = split_dir "/part2.c"
        p3 = split_dir "/part3.c"
        # The Go frontend's generated C carries no static inline definitions,
        # so the inline header is legitimately empty for it. Create both
        # shared headers up front; the first real line reopens and truncates
        # each one, so output bytes are unchanged for every input.
        printf "" > h
        close(h)
        printf "" > ih
        close(ih)
        print "#include \"alder_split.h\"" > p0
        print "#include \"alder_split_inline.h\"" > p0
        print "#include \"alder_split.h\"" > p1
        print "#include \"alder_split_inline.h\"" > p1
        print "#include \"alder_split.h\"" > p2
        print "#include \"alder_split_inline.h\"" > p2
        print "#include \"alder_split.h\"" > p3
        print "#include \"alder_split_inline.h\"" > p3
    }
}

{
    if (mode == "plan") {
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
        next
    }

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
    if (mode == "plan") {
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
    } else {
        if (hdr_end < 1 || entry <= hdr_end ||
            cut1 <= hdr_end || cut1 >= cut2 || cut2 >= cut3 || cut3 >= entry)
            fail("cut points are not strictly ordered")
        if (in_inline) fail("unterminated static-inline block")
        total = hdr_lines + ih_lines + p0n + p1n + p2n + p3n
        if (total != NR) fail("wrote " total " of " NR " lines")
        if (p0n == 0 || p1n == 0 || p2n == 0 || p3n == 0) fail("empty part")
    }
}
