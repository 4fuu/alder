// M6 project discovery deliberately uses only exact host requests.  The byte
// ranges below refer to ProjectPlanRec.bytes; no host-owned pointer escapes.
import c alderhost_project_mode: fn() -> Bool
import c alderhost_project_action: fn() -> U64
import c alderhost_manifest_len: fn() -> U64
import c alderhost_manifest_byte: fn(U64) -> U8
import c alderhost_target_len: fn() -> U64
import c alderhost_target_byte: fn(U64) -> U8
import c alderhost_profile_len: fn() -> U64
import c alderhost_profile_byte: fn(U64) -> U8
import c alderhost_triple_len: fn() -> U64
import c alderhost_triple_byte: fn(U64) -> U8
import c alderhost_source_request_reset: fn() -> Bool
import c alderhost_source_request_byte: fn(U8) -> Bool
import c alderhost_source_request_finish: fn() -> U64
import c alderhost_sources_sort: fn() -> Bool
import c alderhost_project_output_reset: fn(U64) -> Bool
import c alderhost_project_output_byte: fn(U8) -> Bool
import c alderhost_project_output_finish: fn() -> Bool
import c alderhost_project_target_kind: fn(U64) -> Bool
import c alderhost_project_selected_kind: fn() -> U64
import c alderhost_project_entry_source_set: fn(U64) -> Bool
import c alderhost_sysroot_available: fn() -> Bool
import c alderhost_sysroot_request_reset: fn() -> Bool
import c alderhost_sysroot_request_byte: fn(U8) -> Bool
import c alderhost_sysroot_request_finish: fn() -> U64
import c alderhost_generated_source_reset: fn() -> Bool
import c alderhost_generated_source_path_byte: fn(U8) -> Bool
import c alderhost_generated_source_text_byte: fn(U8) -> Bool
import c alderhost_generated_source_finish: fn() -> U64

type ProjectTargetRec {
    name_start: U64
    name_end: U64
    root_start: U64
    root_end: U64
    kind: U64
}
type ProjectModuleRec {
    name_start: U64
    name_end: U64
    source: U64
    mark: U64
}
type ProjectEdgeRec {
    from: U64
    name_start: U64
    name_end: U64
    to: U64
}
type ProjectScanRec {
    at: U64
    valid: Bool
}
type ProjectPathRec {
    start: U64
    end: U64
    at: U64
    valid: Bool
}
type ProjectPlanRec {
    bytes: __s0_Buffer(U8)
    targets: __s0_Buffer(ProjectTargetRec)
    modules: __s0_Buffer(ProjectModuleRec)
    edges: __s0_Buffer(ProjectEdgeRec)
    package_start: U64
    package_end: U64
    selected: U64
    action: U64
    profile: U64
    triple: U64
}

enum ProjectBuild {
    ProjectBuilt(value: ProjectPlanRec)
    ProjectRejected(message: U64)
}

fn project_mode() -> Bool { return unsafe c { alderhost_project_mode() } }
fn project_action() -> U64 { return unsafe c { alderhost_project_action() } }
fn project_binary() -> Bool { return unsafe c { alderhost_project_selected_kind() } == 1 }
fn project_fail(message: U64) -> I32 {
    if message == 1 { return driver_failure(2, "package", "malformed project manifest") }
    if message == 2 { return driver_failure(2, "package", "project manifest has a duplicate key or table") }
    if message == 3 { return driver_failure(2, "package", "project manifest is missing a required field") }
    if message == 4 { return driver_failure(2, "package", "project feature is not available before its roadmap gate") }
    if message == 5 { return driver_failure(2, "package", "a target must be specified when the package has multiple targets") }
    if message == 6 { return driver_failure(2, "package", "requested package target does not exist") }
    if message == 7 { return driver_failure(2, "package", "source module declaration does not match its canonical path") }
    if message == 8 { return driver_failure(2, "package", "local module source is unavailable") }
    if message == 9 { return driver_failure(2, "package", "duplicate module in package") }
    if message == 10 { return driver_failure(2, "package", "module import cycle") }
    if message == 11 { return driver_failure(2, "package", "no installed Alder sysroot is available for a core or std import") }
    if message == 12 { return driver_failure(2, "package", "compiler storage failure while preparing project") }
    if message == 13 { return driver_failure(2, "package", "a required sysroot module is unavailable in the installed sysroot") }
    if message == 14 { return driver_failure(2, "package", "the package name core or std is reserved") }
    return driver_failure(2, "package", "compiler storage failure while preparing project")
}

fn project_equal(b: __s0_Buffer(U8), start: U64, end: U64, s: __s0_String) -> Bool {
    if end - start != len(s) { return false }
    var i: U64 = 0
    while i < len(s) {
        if __s0_buffer_get(U8, b, start + i) != s[i] { return false }
        i = i + 1
    }
    return true
}
fn project_range_equal(b: __s0_Buffer(U8), a: U64, ae: U64, c: U64, ce: U64) -> Bool {
    if ae - a != ce - c { return false }
    var i: U64 = 0
    while a + i < ae {
        if __s0_buffer_get(U8, b, a + i) != __s0_buffer_get(U8, b, c + i) { return false }
        i = i + 1
    }
    return true
}
fn project_space(c: U8) -> Bool { return c == 32 || c == 9 || c == 13 }
fn project_ident(c: U8) -> Bool { return alpha(c) || digit(c) }

fn project_name_byte(c: U8, first: Bool) -> Bool {
    if c >= 97 && c <= 122 { return true }
    if !first && (digit(c) || c == 95 || c == 45) { return true }
    return false
}

fn project_name(b: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    if start >= end { return false }
    var at = start
    while at < end {
        if !project_name_byte(__s0_buffer_get(U8, b, at), at == start) { return false }
        at = at + 1
    }
    return true
}

fn project_package_name(b: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    if start >= end { return false }
    var at = start
    while at < end {
        let c = __s0_buffer_get(U8, b, at)
        if !((c >= 97 && c <= 122) || (at > start && (digit(c) || c == 95))) { return false }
        at = at + 1
    }
    return true
}

fn project_manifest_path(b: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    if start >= end { return false }
    var component = start
    var at = start
    while at <= end {
        if at == end || __s0_buffer_get(U8, b, at) == 47 {
            if at == component || (at - component == 1 && __s0_buffer_get(U8, b, component) == 46) || (at - component == 2 && __s0_buffer_get(U8, b, component) == 46 && __s0_buffer_get(U8, b, component + 1) == 46) { return false }
            component = at + 1
        } else {
            let c = __s0_buffer_get(U8, b, at)
            if c == 92 || c == 58 || c < 32 || c >= 127 { return false }
        }
        at = at + 1
    }
    return true
}

// Parse one basic TOML string.  Escapes are validated and retained encoded;
// manifest names and paths consequently remain ASCII and need no decoding.
fn project_string(b: __s0_Buffer(U8), start: U64, end: U64) -> U64 {
    if start >= end || __s0_buffer_get(U8, b, start) != 34 { return 0 }
    var at = start + 1
    while at < end {
        let c = __s0_buffer_get(U8, b, at)
        if c == 34 { if at + 1 == end { return at } else { return 0 } }
        if c < 32 || c >= 128 { return 0 }
        if c == 92 {
            at = at + 1
            if at >= end { return 0 }
            let e = __s0_buffer_get(U8, b, at)
            if e != 34 && e != 92 && e != 110 && e != 114 && e != 116 { return 0 }
        }
        at = at + 1
    }
    return 0
}

fn project_copy_manifest(d: Domain) -> Result(__s0_Buffer(U8), __s0_Error) {
    var b = try __s0_buffer_new(U8, d)
    var i: U64 = 0
    let n = unsafe c { alderhost_manifest_len() }
    while i < n {
        b = try __s0_buffer_append(U8, d, b, unsafe c { alderhost_manifest_byte(i) })
        i = i + 1
    }
    return Ok(b)
}

fn project_option_equal(kind: U64, b: __s0_Buffer(U8), s: U64, e: U64) -> Bool {
    var n: U64 = unsafe c { alderhost_target_len() }
    if kind == 2 { n = unsafe c { alderhost_profile_len() } }
    if kind == 3 { n = unsafe c { alderhost_triple_len() } }
    if n != e - s { return false }
    var i: U64 = 0
    while i < n {
        var c = unsafe c { alderhost_target_byte(i) }
        if kind == 2 { c = unsafe c { alderhost_profile_byte(i) } }
        if kind == 3 { c = unsafe c { alderhost_triple_byte(i) } }
        if c != __s0_buffer_get(U8, b, s + i) { return false }
        i = i + 1
    }
    return true
}

fn project_parse_manifest(d: Domain, b: __s0_Buffer(U8)) -> Result(ProjectBuild, __s0_Error) {
    var targets = try __s0_buffer_new(ProjectTargetRec, d)
    var modules = try __s0_buffer_new(ProjectModuleRec, d)
    var edges = try __s0_buffer_new(ProjectEdgeRec, d)
    var package_s: U64 = 0
    var package_e: U64 = 0
    var version = false
    var manifest = false
    var edition = false
    var package_table = false
    var table: U64 = 0
    var current: U64 = 0
    var at: U64 = 0
    let n = __s0_buffer_len(U8, b)
    while at < n {
        var end = at
        var quote = false
        var escape = false
        var line_done = false
        while end < n && __s0_buffer_get(U8, b, end) != 10 && !line_done {
            let c = __s0_buffer_get(U8, b, end)
            if c == 34 && !escape { quote = !quote }
            if c == 35 && !quote { line_done = true }
            if !line_done {
                escape = c == 92 && !escape
                if c != 92 { escape = false }
                end = end + 1
            }
        }
        var ls = at
        while ls < end && project_space(__s0_buffer_get(U8, b, ls)) { ls = ls + 1 }
        var le = end
        while le > ls && project_space(__s0_buffer_get(U8, b, le - 1)) { le = le - 1 }
        if quote { return Ok(ProjectRejected(1)) }
        if ls < le {
            if __s0_buffer_get(U8, b, ls) == 91 {
                if __s0_buffer_get(U8, b, le - 1) != 93 { return Ok(ProjectRejected(1)) }
                let ts = ls + 1
                let te = le - 1
                if project_equal(b, ts, te, "package") {
                    if package_table { return Ok(ProjectRejected(2)) }
                    package_table = true
                    table = 1
                    current = 0
                } else {
                    if te - ts > 8 && project_equal(b, ts, ts + 8, "targets.") {
                        if !project_name(b, ts + 8, te) { return Ok(ProjectRejected(1)) }
                        var k: U64 = 0
                        while k < __s0_buffer_len(ProjectTargetRec, targets) {
                            let old = __s0_buffer_get(ProjectTargetRec, targets, k)
                            if project_range_equal(b, old.name_start, old.name_end, ts + 8, te) { return Ok(ProjectRejected(2)) }
                            k = k + 1
                        }
                        targets = try __s0_buffer_append(ProjectTargetRec, d, targets, ProjectTargetRec(name_start: ts + 8, name_end: te, root_start: 0, root_end: 0, kind: 0))
                        current = __s0_buffer_len(ProjectTargetRec, targets)
                        table = 2
                    } else {
                        if project_equal(b, ts, te, "dependencies") || project_equal(b, ts, te, "workspace") || project_equal(b, ts, te, "native") || project_equal(b, ts, te, "lock") || project_equal(b, ts, te, "git") { return Ok(ProjectRejected(4)) }
                        if te - ts >= 8 && project_equal(b, ts, ts + 8, "profile.") { return Ok(ProjectRejected(4)) }
                        return Ok(ProjectRejected(1))
                    }
                }
            } else {
                var eq = ls
                while eq < le && __s0_buffer_get(U8, b, eq) != 61 { eq = eq + 1 }
                if eq == le { return Ok(ProjectRejected(1)) }
                var ke = eq
                while ke > ls && project_space(__s0_buffer_get(U8, b, ke - 1)) { ke = ke - 1 }
                var vs = eq + 1
                while vs < le && project_space(__s0_buffer_get(U8, b, vs)) { vs = vs + 1 }
                var handled = false
                if table == 0 && project_equal(b, ls, ke, "manifest") {
                    if manifest || !project_equal(b, vs, le, "1") { return Ok(ProjectRejected(2)) }
                    manifest = true
                    handled = true
                }
                if table == 0 && project_equal(b, ls, ke, "edition") {
                    if edition || !project_equal(b, vs, le, "\"1\"") { return Ok(ProjectRejected(2)) }
                    edition = true
                    handled = true
                }
                if table == 1 && project_equal(b, ls, ke, "name") {
                    let q = project_string(b, vs, le)
                    if package_e != 0 || q == 0 || !project_package_name(b, vs + 1, q) { return Ok(ProjectRejected(2)) }
                    if project_equal(b, vs + 1, q, "core") || project_equal(b, vs + 1, q, "std") { return Ok(ProjectRejected(14)) }
                    package_s = vs + 1
                    package_e = q
                    handled = true
                }
                if table == 1 && project_equal(b, ls, ke, "version") {
                    let q = project_string(b, vs, le)
                    if version || q == 0 || q == vs + 1 { return Ok(ProjectRejected(2)) }
                    version = true
                    handled = true
                }
                if table == 2 && current != 0 {
                    let old = __s0_buffer_get(ProjectTargetRec, targets, current - 1)
                    let q = project_string(b, vs, le)
                    if q == 0 || q == vs + 1 { return Ok(ProjectRejected(1)) }
                    if project_equal(b, ls, ke, "kind") {
                        if old.kind != 0 { return Ok(ProjectRejected(2)) }
                        var kind: U64 = 0
                        if project_equal(b, vs + 1, q, "bin") { kind = 1 }
                        if project_equal(b, vs + 1, q, "lib") { kind = 2 }
                        if kind == 0 { return Ok(ProjectRejected(1)) }
                        __s0_buffer_set(ProjectTargetRec, targets, current - 1, ProjectTargetRec(name_start: old.name_start, name_end: old.name_end, root_start: old.root_start, root_end: old.root_end, kind: kind))
                        handled = true
                    } else {
                        if !project_equal(b, ls, ke, "root") { return Ok(ProjectRejected(1)) }
                        if old.root_end != 0 || q - (vs + 1) < 7 || !project_equal(b, vs + 1, vs + 5, "src/") || !project_equal(b, q - 3, q, ".al") || !project_manifest_path(b, vs + 1, q) { return Ok(ProjectRejected(1)) }
                        __s0_buffer_set(ProjectTargetRec, targets, current - 1, ProjectTargetRec(name_start: old.name_start, name_end: old.name_end, root_start: vs + 1, root_end: q, kind: old.kind))
                        handled = true
                    }
                }
                if !handled { return Ok(ProjectRejected(1)) }
            }
        }
        while end < n && __s0_buffer_get(U8, b, end) != 10 { end = end + 1 }
        at = end + 1
    }
    if !manifest || !edition || package_e == 0 || !version || __s0_buffer_len(ProjectTargetRec, targets) == 0 { return Ok(ProjectRejected(3)) }
    var i: U64 = 0
    while i < __s0_buffer_len(ProjectTargetRec, targets) {
        let t = __s0_buffer_get(ProjectTargetRec, targets, i)
        if t.kind == 0 || t.root_end == 0 { return Ok(ProjectRejected(3)) }
        i = i + 1
    }
    var selected: U64 = 0
    let tn = unsafe c { alderhost_target_len() }
    if tn == 0 {
        if __s0_buffer_len(ProjectTargetRec, targets) != 1 { return Ok(ProjectRejected(5)) }
        selected = 1
    } else {
        i = 0
        while i < __s0_buffer_len(ProjectTargetRec, targets) {
            let t = __s0_buffer_get(ProjectTargetRec, targets, i)
            if project_option_equal(1, b, t.name_start, t.name_end) { selected = i + 1 }
            i = i + 1
        }
        if selected == 0 { return Ok(ProjectRejected(6)) }
    }
    let pn = unsafe c { alderhost_profile_len() }
    var profile: U64 = 1
    if pn != 0 {
        profile = 0
        if pn == 5 {
            let expected: __s0_String = "debug"
            var ok = true
            var z: U64 = 0
            while z < 5 {
                if unsafe c { alderhost_profile_byte(z) } != expected[z] { ok = false }
                z = z + 1
            }
            if ok { profile = 1 }
        }
        if pn == 7 {
            let expected: __s0_String = "release"
            var ok = true
            var z: U64 = 0
            while z < 7 {
                if unsafe c { alderhost_profile_byte(z) } != expected[z] { ok = false }
                z = z + 1
            }
            if ok { profile = 2 }
        }
        if profile == 0 { return Ok(ProjectRejected(1)) }
    }
    let xn = unsafe c { alderhost_triple_len() }
    if xn == 0 { return Ok(ProjectRejected(1)) }
    var x: U64 = 0
    while x < xn {
        let c = unsafe c { alderhost_triple_byte(x) }
        if !((c >= 97 && c <= 122) || digit(c) || c == 45 || c == 95) { return Ok(ProjectRejected(1)) }
        x = x + 1
    }
    return Ok(ProjectBuilt(ProjectPlanRec(bytes: b, targets: targets, modules: modules, edges: edges, package_start: package_s, package_end: package_e, selected: selected, action: project_action(), profile: profile, triple: 1)))
}

fn project_request(plan: ProjectPlanRec, start: U64, end: U64) -> U64 {
    if !unsafe c { alderhost_source_request_reset() } { return 0 }
    var i = start
    while i < end {
        let byte = __s0_buffer_get(U8, plan.bytes, i)
        if !unsafe c { alderhost_source_request_byte(byte) } { return 0 }
        i = i + 1
    }
    return unsafe c { alderhost_source_request_finish() }
}

fn project_source_byte(source: U64, at: U64) -> U8 {
    return unsafe c { alderhost_source_text_byte(source - 1, at) }
}

fn project_source_word(source: U64, start: U64, end: U64, word: __s0_String) -> Bool {
    if end - start != len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if project_source_byte(source, start + at) != word[at] { return false }
        at = at + 1
    }
    return true
}

fn project_source_token(source: U64, start: U64, end: U64, word: __s0_String) -> Bool {
    if !project_source_word(source, start, end, word) { return false }
    if start > 0 && project_source_ident_continue(project_source_byte(source, start - 1)) { return false }
    let source_end = unsafe c { alderhost_source_text_len(source - 1) }
    if end < source_end && project_source_ident_continue(project_source_byte(source, end)) { return false }
    return true
}

fn project_source_space(byte: U8) -> Bool {
    return byte == 32 || byte == 9 || byte == 10 || byte == 13
}

fn project_source_ident_start(byte: U8) -> Bool {
    return byte == 95 || (byte >= 97 && byte <= 122)
}

fn project_source_ident_continue(byte: U8) -> Bool {
    return project_source_ident_start(byte) || digit(byte)
}

fn project_skip_source_trivia(source: U64, initial: U64, end: U64) -> ProjectScanRec {
    var at = initial
    var valid = true
    var moving = true
    while moving && at < end {
        moving = false
        while at < end && project_source_space(project_source_byte(source, at)) {
            at = at + 1
            moving = true
        }
        if at + 1 < end && project_source_byte(source, at) == 47 && project_source_byte(source, at + 1) == 47 {
            at = at + 2
            while at < end && project_source_byte(source, at) != 10 { at = at + 1 }
            moving = true
        }
        if at + 1 < end && project_source_byte(source, at) == 47 && project_source_byte(source, at + 1) == 42 {
            at = at + 2
            var closed = false
            while at + 1 < end && !closed {
                if project_source_byte(source, at) == 42 && project_source_byte(source, at + 1) == 47 {
                    at = at + 2
                    closed = true
                } else { at = at + 1 }
            }
            if !closed { valid = false }
            moving = closed
        }
    }
    return ProjectScanRec(at: at, valid: valid)
}

fn project_parse_source_path(source: U64, initial: U64, end: U64) -> ProjectPathRec {
    if initial >= end || !project_source_ident_start(project_source_byte(source, initial)) { return ProjectPathRec(start: initial, end: initial, at: initial, valid: false) }
    let start = initial
    var at = initial + 1
    while at < end && project_source_ident_continue(project_source_byte(source, at)) { at = at + 1 }
    var done = false
    var valid = true
    while !done && at < end {
        if project_source_byte(source, at) != 46 { done = true }
        if !done {
            at = at + 1
            if at >= end || !project_source_ident_start(project_source_byte(source, at)) {
                valid = false
                done = true
            } else {
                at = at + 1
                while at < end && project_source_ident_continue(project_source_byte(source, at)) { at = at + 1 }
            }
        }
    }
    return ProjectPathRec(start: start, end: at, at: at, valid: valid)
}

fn project_source_module_path(source: U64, start: U64, end: U64) -> Bool {
    var segment = start
    var at = start
    while at <= end {
        if at == end || project_source_byte(source, at) == 46 {
            if at == segment { return false }
            segment = at + 1
        } else {
            let c = project_source_byte(source, at)
            if !((c >= 97 && c <= 122) || (at > segment && (digit(c) || c == 95))) { return false }
        }
        at = at + 1
    }
    return true
}

fn project_manifest_source_equal(plan: ProjectPlanRec, source: U64, source_start: U64, source_end: U64, manifest_start: U64, manifest_end: U64) -> Bool {
    if source_end - source_start != manifest_end - manifest_start { return false }
    var at: U64 = 0
    while source_start + at < source_end {
        if project_source_byte(source, source_start + at) != __s0_buffer_get(U8, plan.bytes, manifest_start + at) { return false }
        at = at + 1
    }
    return true
}

fn project_source_path_is(source: U64, word: __s0_String) -> Bool {
    let end = unsafe c { alderhost_source_path_len(source - 1) }
    if end != len(word) { return false }
    var at: U64 = 0
    while at < end {
        if unsafe c { alderhost_source_path_byte(source - 1, at) } != word[at] { return false }
        at = at + 1
    }
    return true
}

fn project_declared_module_matches(plan: ProjectPlanRec, source: U64, start: U64, end: U64) -> Bool {
    if project_source_path_is(source, "src/lib.al") { return project_manifest_source_equal(plan, source, start, end, plan.package_start, plan.package_end) }
    let path_end = unsafe c { alderhost_source_path_len(source - 1) }
    if path_end < 8 || end - start != (plan.package_end - plan.package_start) + 1 + path_end - 7 { return false }
    var at: U64 = 0
    while plan.package_start + at < plan.package_end {
        if project_source_byte(source, start + at) != __s0_buffer_get(U8, plan.bytes, plan.package_start + at) { return false }
        at = at + 1
    }
    if project_source_byte(source, start + at) != 46 { return false }
    at = at + 1
    var path_at: U64 = 4
    while path_at < path_end - 3 {
        var expected = unsafe c { alderhost_source_path_byte(source - 1, path_at) }
        if expected == 47 { expected = 46 }
        if project_source_byte(source, start + at) != expected { return false }
        at = at + 1
        path_at = path_at + 1
    }
    return start + at == end
}

fn project_request_literal(word: __s0_String) -> Bool {
    var at: U64 = 0
    while at < len(word) {
        if !unsafe c { alderhost_source_request_byte(word[at]) } { return false }
        at = at + 1
    }
    return true
}

fn project_request_module(plan: ProjectPlanRec, source: U64, start: U64, end: U64) -> U64 {
    let package_length = plan.package_end - plan.package_start
    if end - start < package_length || !project_manifest_source_equal(plan, source, start, start + package_length, plan.package_start, plan.package_end) { return 0 }
    if !unsafe c { alderhost_source_request_reset() } { return 0 }
    if end - start == package_length {
        if !project_request_literal("src/lib.al") { return 0 }
        return unsafe c { alderhost_source_request_finish() }
    }
    if project_source_byte(source, start + package_length) != 46 || !project_request_literal("src/") { return 0 }
    var at = start + package_length + 1
    while at < end {
        var byte = project_source_byte(source, at)
        if byte == 46 { byte = 47 }
        if !unsafe c { alderhost_source_request_byte(byte) } { return 0 }
        at = at + 1
    }
    if !project_request_literal(".al") { return 0 }
    return unsafe c { alderhost_source_request_finish() }
}

// A rooted import is exactly `core`, `std`, `core.…`, or `std.…`.  Package
// roots that merely start with the same letters, such as `corefoo`, stay
// ordinary package imports.
fn project_source_rooted(source: U64, start: U64, end: U64) -> Bool {
    if end - start == 4 && project_source_word(source, start, start + 4, "core") { return true }
    if end - start > 4 && project_source_word(source, start, start + 4, "core") && project_source_byte(source, start + 4) == 46 { return true }
    if end - start == 3 && project_source_word(source, start, start + 3, "std") { return true }
    if end - start > 3 && project_source_word(source, start, start + 3, "std") && project_source_byte(source, start + 3) == 46 { return true }
    return false
}

fn project_sysroot_request_byte(byte: U8) -> Bool {
    return unsafe c { alderhost_sysroot_request_byte(byte) }
}

// Request one sysroot source for a rooted import.  A bare root maps to
// `<root>.al`; every dot below the root maps to a slash, so `core.option`
// requests `core/option.al` inside the installed sysroot and never inside the
// project.
fn project_request_sysroot_module(source: U64, start: U64, end: U64) -> U64 {
    if !project_source_rooted(source, start, end) { return 0 }
    if !unsafe c { alderhost_sysroot_request_reset() } { return 0 }
    var at = start
    while at < end {
        var byte = project_source_byte(source, at)
        if byte == 46 { byte = 47 }
        if !project_sysroot_request_byte(byte) { return 0 }
        at = at + 1
    }
    if !project_sysroot_request_byte(46) { return 0 }
    if !project_sysroot_request_byte(97) { return 0 }
    if !project_sysroot_request_byte(108) { return 0 }
    return unsafe c { alderhost_sysroot_request_finish() }
}

fn project_request_sysroot_literal(word: __s0_String) -> U64 {
    if !unsafe c { alderhost_sysroot_request_reset() } { return 0 }
    var at: U64 = 0
    while at < len(word) {
        if !project_sysroot_request_byte(word[at]) { return 0 }
        at = at + 1
    }
    return unsafe c { alderhost_sysroot_request_finish() }
}

fn project_source_mentions_error(source: U64) -> Bool {
    let end = unsafe c { alderhost_source_text_len(source - 1) }
    var at: U64 = 0
    while at + 5 <= end {
        if project_source_byte(source, at) == 69 && project_source_byte(source, at + 1) == 114 && project_source_byte(source, at + 2) == 114 && project_source_byte(source, at + 3) == 111 && project_source_byte(source, at + 4) == 114 { return true }
        at = at + 1
    }
    return false
}

// core.error is a prelude source, but it still lives in the installed sysroot.
// Load it only when the project mentions the Error family; unrelated projects
// keep their existing source closure and build plan. An explicit core.error
// import has already loaded the same path, so this is a no-op then.
fn project_prepare_error_prelude() -> Bool {
    if !unsafe c { alderhost_sysroot_available() } { return true }
    let count = unsafe c { alderhost_source_count() }
    var source: U64 = 1
    while source <= count {
        if project_source_path_is(source, "core/error.al") { return true }
        source = source + 1
    }
    source = 1
    var required = false
    while source <= count {
        if project_source_mentions_error(source) { required = true }
        source = source + 1
    }
    if !required { return true }
    return project_request_sysroot_literal("core/error.al") != 0
}

type ProjectEntryShapeRec {
    kind: U64
    error_start: U64
    error_end: U64
}

fn project_entry_ident_start(byte: U8) -> Bool {
    return byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

fn project_entry_type_end(source: U64, initial: U64, end: U64) -> U64 {
    if initial >= end || !project_entry_ident_start(project_source_byte(source, initial)) { return initial }
    var at = initial + 1
    while at < end && (project_entry_ident_start(project_source_byte(source, at)) || digit(project_source_byte(source, at)) || project_source_byte(source, at) == 46) { at = at + 1 }
    if at < end && project_source_byte(source, at) == 40 {
        var depth: U64 = 0
        while at < end {
            let byte = project_source_byte(source, at)
            if byte == 40 { depth = depth + 1 }
            if byte == 41 { if depth == 0 { return at } else { depth = depth - 1 } }
            at = at + 1
        }
    }
    return at
}

fn project_entry_result_type(source: U64, initial: U64, end: U64) -> ProjectEntryShapeRec {
    let start = project_skip_source_trivia(source, initial, end)
    if !start.valid || start.at >= end { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
    var kind: U64 = 0
    if project_source_token(source, start.at, start.at + 4, "Unit") { kind = 1 }
    if project_source_token(source, start.at, start.at + 3, "I32") { kind = 0 }
    if project_source_token(source, start.at, start.at + 6, "Result") {
            let open = project_skip_source_trivia(source, start.at + 6, end)
        if !open.valid || open.at >= end || project_source_byte(source, open.at) != 40 { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
        let first = project_skip_source_trivia(source, open.at + 1, end)
        if !first.valid { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
            if project_source_token(source, first.at, first.at + 4, "Unit") { kind = 2 }
        if project_source_token(source, first.at, first.at + 3, "I32") { kind = 3 }
        if kind == 0 { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
        var at = project_entry_type_end(source, first.at, end)
        at = project_skip_source_trivia(source, at, end).at
            if at >= end || project_source_byte(source, at) != 44 { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
        let error_start_scan = project_skip_source_trivia(source, at + 1, end)
            if !error_start_scan.valid || error_start_scan.at >= end { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
        var error_end = project_entry_type_end(source, error_start_scan.at, end)
            var trim = error_end
        while trim > error_start_scan.at && project_source_space(project_source_byte(source, trim - 1)) { trim = trim - 1 }
        if trim == error_start_scan.at { return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0) }
            return ProjectEntryShapeRec(kind: kind, error_start: error_start_scan.at, error_end: trim)
    }
    return ProjectEntryShapeRec(kind: kind, error_start: 0, error_end: 0)
}

fn project_entry_shape(source: U64) -> ProjectEntryShapeRec {
    let end = unsafe c { alderhost_source_text_len(source - 1) }
    var at: U64 = 0
    while at + 4 <= end {
        if project_source_token(source, at, at + 4, "main") {
            var previous = at
            while previous > 0 && project_source_space(project_source_byte(source, previous - 1)) { previous = previous - 1 }
            if previous >= 2 && project_source_token(source, previous - 2, previous, "fn") {
                let open = project_skip_source_trivia(source, at + 4, end)
                if open.valid && open.at < end && project_source_byte(source, open.at) == 40 {
                    var depth: U64 = 1
                    var after = open.at + 1
                    while after < end && depth > 0 {
                        let byte = project_source_byte(source, after)
                        if byte == 40 { depth = depth + 1 }
                        if byte == 41 { depth = depth - 1 }
                        after = after + 1
                    }
                    let arrow = project_skip_source_trivia(source, after, end)
                    if arrow.valid && arrow.at + 1 < end && project_source_byte(source, arrow.at) == 45 && project_source_byte(source, arrow.at + 1) == 62 {
                        return project_entry_result_type(source, arrow.at + 2, end)
                    }
                }
            }
        }
        at = at + 1
    }
    return ProjectEntryShapeRec(kind: 0, error_start: 0, error_end: 0)
}

fn project_source_entry_error_impl(source: U64, start: U64, end: U64) -> Bool {
    let text_end = unsafe c { alderhost_source_text_len(source - 1) }
    var at: U64 = 0
    while at + 4 <= text_end {
        if project_source_token(source, at, at + 4, "impl") {
            var scan = project_skip_source_trivia(source, at + 4, text_end)
            if scan.valid && scan.at < text_end && project_source_byte(source, scan.at) == 40 {
                var depth: U64 = 1
                var close = scan.at + 1
                while close < text_end && depth > 0 {
                    let byte = project_source_byte(source, close)
                    if byte == 40 { depth = depth + 1 }
                    if byte == 41 { depth = depth - 1 }
                    close = close + 1
                }
                scan = project_skip_source_trivia(source, close, text_end)
            }
            if scan.valid && project_source_token(source, scan.at, scan.at + 5, "Error") {
                let after_error = project_skip_source_trivia(source, scan.at + 5, text_end)
                if after_error.valid && project_source_token(source, after_error.at, after_error.at + 3, "for") {
                    let type_at = project_skip_source_trivia(source, after_error.at + 3, text_end)
                    if type_at.valid && type_at.at < text_end {
                        let type_end = project_entry_type_end(source, type_at.at, text_end)
                        if type_end == end && type_at.at == start { return true }
                        if type_end - type_at.at == end - start {
                            var same = true
                            var offset: U64 = 0
                            while offset < end - start {
                                if project_source_byte(source, type_at.at + offset) != project_source_byte(source, start + offset) { same = false }
                                offset = offset + 1
                            }
                            if same { return true }
                        }
                    }
                }
            }
        }
        at = at + 1
    }
    return false
}

fn project_entry_has_error_impl(start: U64, end: U64) -> Bool {
    let count = unsafe c { alderhost_source_count() }
    var source: U64 = 1
    while source <= count {
        if project_source_entry_error_impl(source, start, end) { return true }
        source = source + 1
    }
    return false
}

fn project_generated_path_byte(byte: U8) -> Bool {
    return unsafe c { alderhost_generated_source_path_byte(byte) }
}

fn project_generated_text_byte(byte: U8) -> Bool {
    return unsafe c { alderhost_generated_source_text_byte(byte) }
}

fn project_generated_write_literal(word: __s0_String) -> Bool {
    var at: U64 = 0
    while at < len(word) {
        if !project_generated_text_byte(word[at]) { return false }
        at = at + 1
    }
    return true
}

fn project_generated_write_source_range(source: U64, start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !project_generated_text_byte(project_source_byte(source, at)) { return false }
        at = at + 1
    }
    return true
}

fn project_request_core_error() -> Bool {
    if !unsafe c { alderhost_sysroot_available() } { return false }
    let count = unsafe c { alderhost_source_count() }
    var source: U64 = 1
    while source <= count {
        if project_source_path_is(source, "core/error.al") { return true }
        source = source + 1
    }
    return project_request_sysroot_literal("core/error.al") != 0
}

fn project_prepare_entry_wrapper(plan: ProjectPlanRec) -> Bool {
    let entry = unsafe c { alderhost_project_entry_source() }
    if entry == 0 { return true }
    let shape = project_entry_shape(entry)
    if shape.kind == 0 { return true }
    if shape.kind != 1 && !project_request_core_error() { return false }
    let module_rec = project_module_for_source(plan, entry)
    if module_rec.source == 0 { return false }
    let path: __s0_String = "src/__alder_entry.al"
    if !unsafe c { alderhost_generated_source_reset() } { return false }
    var at: U64 = 0
    while at < len(path) {
        if !project_generated_path_byte(path[at]) { return false }
        at = at + 1
    }
    if !project_generated_write_literal("module alder_entry\n\n") { return false }
    if !project_generated_write_literal("import ") || !project_generated_write_source_range(module_rec.source, module_rec.name_start, module_rec.name_end) || !project_generated_write_literal(" as entry\n") { return false }
    if shape.kind != 1 {
        if !project_generated_write_literal("import core.error as cerror\n") { return false }
    }
    if !project_generated_write_literal("\npub fn main() -> I32 {\n") { return false }
    if shape.kind == 1 {
        if !project_generated_write_literal("    entry.main()\n    return 0\n") { return false }
    } else {
        if !project_generated_write_literal("    match entry.main() {\n") { return false }
        if shape.kind == 3 { if !project_generated_write_literal("        Ok(value) => { return value }\n") { return false } }
        else { if !project_generated_write_literal("        Ok(_) => { return 0 }\n") { return false } }
        if project_entry_has_error_impl(shape.error_start, shape.error_end) {
            if !project_generated_write_literal("        Err(error) => {\n            cerror.program_error_chain(error)\n            return 1\n        }\n") { return false }
        } else {
            if !project_generated_write_literal("        Err(error) => {\n            cerror.program_error_display(error)\n            return 1\n        }\n") { return false }
        }
        if !project_generated_write_literal("    }\n    return 1\n") { return false }
    }
    if !project_generated_write_literal("}\n") { return false }
    let generated = unsafe c { alderhost_generated_source_finish() }
    if generated == 0 { return false }
    return unsafe c { alderhost_project_entry_source_set(generated) }
}

fn project_source_path_prefix_is(source: U64, word: __s0_String) -> Bool {
    let end = unsafe c { alderhost_source_path_len(source - 1) }
    if end < len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if unsafe c { alderhost_source_path_byte(source - 1, at) } != word[at] { return false }
        at = at + 1
    }
    return true
}

// A sysroot source is any loaded file below the `core` or `std` root.
fn project_source_is_sysroot(source: U64) -> Bool {
    if project_source_path_prefix_is(source, "core/") { return true }
    if project_source_path_prefix_is(source, "std/") { return true }
    if project_source_path_is(source, "core.al") { return true }
    return project_source_path_is(source, "std.al")
}

// A sysroot module declaration must equal its sysroot-relative path with the
// `.al` suffix removed and slashes spelled as dots: core/option.al declares
// `module core.option`.
fn project_declared_sysroot_matches(source: U64, start: U64, end: U64) -> Bool {
    let path_end = unsafe c { alderhost_source_path_len(source - 1) }
    if path_end < 4 || end - start != path_end - 3 { return false }
    var at: U64 = 0
    while at < path_end - 3 {
        var expected = unsafe c { alderhost_source_path_byte(source - 1, at) }
        if expected == 47 { expected = 46 }
        if project_source_byte(source, start + at) != expected { return false }
        at = at + 1
    }
    return true
}

fn project_with_graph(plan: ProjectPlanRec, modules: __s0_Buffer(ProjectModuleRec), edges: __s0_Buffer(ProjectEdgeRec)) -> ProjectPlanRec {
    return ProjectPlanRec(bytes: plan.bytes, targets: plan.targets, modules: modules, edges: edges, package_start: plan.package_start, package_end: plan.package_end, selected: plan.selected, action: plan.action, profile: plan.profile, triple: plan.triple)
}

fn project_scan_source(d: Domain, plan: ProjectPlanRec, source: U64) -> Result(ProjectBuild, __s0_Error) {
    let source_end = unsafe c { alderhost_source_text_len(source - 1) }
    let leading = project_skip_source_trivia(source, 0, source_end)
    if !leading.valid || leading.at + 6 > source_end || !project_source_word(source, leading.at, leading.at + 6, "module") { return Ok(ProjectRejected(7)) }
    let after_module = project_skip_source_trivia(source, leading.at + 6, source_end)
    let declared = project_parse_source_path(source, after_module.at, source_end)
    var declared_ok = false
    if project_source_is_sysroot(source) {
        declared_ok = project_declared_sysroot_matches(source, declared.start, declared.end)
    } else {
        declared_ok = project_declared_module_matches(plan, source, declared.start, declared.end)
    }
    if !after_module.valid || !declared.valid || !project_source_module_path(source, declared.start, declared.end) || !declared_ok { return Ok(ProjectRejected(7)) }
    var module_at: U64 = 0
    while module_at < __s0_buffer_len(ProjectModuleRec, plan.modules) {
        let old = __s0_buffer_get(ProjectModuleRec, plan.modules, module_at)
        if old.source == source { return Ok(ProjectBuilt(plan)) }
        module_at = module_at + 1
    }
    var modules = try __s0_buffer_append(ProjectModuleRec, d, plan.modules, ProjectModuleRec(name_start: declared.start, name_end: declared.end, source: source, mark: 0))
    var edges = plan.edges
    var scan = declared.at
    var depth: U64 = 0
    while scan < source_end {
        let trivia = project_skip_source_trivia(source, scan, source_end)
        if !trivia.valid { return Ok(ProjectRejected(7)) }
        scan = trivia.at
        if scan >= source_end { return Ok(ProjectBuilt(project_with_graph(plan, modules, edges))) }
        let byte = project_source_byte(source, scan)
        if byte == 34 {
            scan = scan + 1
            var closed = false
            while scan < source_end && !closed {
                let string_byte = project_source_byte(source, scan)
                if string_byte == 92 { scan = scan + 2 }
                else {
                    if string_byte == 34 { closed = true }
                    scan = scan + 1
                }
            }
            if !closed { return Ok(ProjectRejected(7)) }
        } else {
            if byte == 123 {
                depth = depth + 1
                scan = scan + 1
            } else {
                if byte == 125 {
                    if depth > 0 { depth = depth - 1 }
                    scan = scan + 1
                } else {
                    if depth == 0 && scan + 6 <= source_end && project_source_token(source, scan, scan + 6, "module") { return Ok(ProjectRejected(7)) }
                    var import_at = scan
                    if depth == 0 && scan + 3 <= source_end && project_source_token(source, scan, scan + 3, "pub") {
                        let after_pub = project_skip_source_trivia(source, scan + 3, source_end)
                        if !after_pub.valid { return Ok(ProjectRejected(7)) }
                        import_at = after_pub.at
                    }
                    if depth == 0 && import_at + 6 <= source_end && project_source_token(source, import_at, import_at + 6, "import") {
                        let after_import = project_skip_source_trivia(source, import_at + 6, source_end)
                        let imported = project_parse_source_path(source, after_import.at, source_end)
                        if !after_import.valid || !imported.valid || !project_source_module_path(source, imported.start, imported.end) { return Ok(ProjectRejected(7)) }
                        var c_import = false
                        if project_source_word(source, imported.start, imported.end, "c") {
                            let after_c = project_skip_source_trivia(source, imported.end, source_end)
                            if after_c.at < source_end {
                                let next = project_source_byte(source, after_c.at)
                                // Both C binding spellings stay out of the
                                // module graph: `import c name` (the S0
                                // bridge) and `import c "header.h" as name
                                // { ... }` (the M8 binding block, whose
                                // header is a string literal, not a module
                                // path).
                                if project_source_ident_start(next) { c_import = true }
                                else { if next == 34 { c_import = true } }
                            }
                        }
                        if !c_import {
                            var target: U64 = 0
                            if project_source_rooted(source, imported.start, imported.end) {
                                if !unsafe c { alderhost_sysroot_available() } { return Ok(ProjectRejected(11)) }
                                target = project_request_sysroot_module(source, imported.start, imported.end)
                                if target == 0 { return Ok(ProjectRejected(13)) }
                            } else {
                                target = project_request_module(plan, source, imported.start, imported.end)
                                if target == 0 { return Ok(ProjectRejected(8)) }
                            }
                            var prior: U64 = 0
                            while prior < __s0_buffer_len(ProjectEdgeRec, edges) {
                                let old = __s0_buffer_get(ProjectEdgeRec, edges, prior)
                                if old.from == source && !project_range_less(source, old.name_start, old.name_end, source, imported.start, imported.end) && !project_range_less(source, imported.start, imported.end, source, old.name_start, old.name_end) { return Ok(ProjectRejected(7)) }
                                prior = prior + 1
                            }
                            edges = try __s0_buffer_append(ProjectEdgeRec, d, edges, ProjectEdgeRec(from: source, name_start: imported.start, name_end: imported.end, to: target))
                        }
                        scan = imported.at
                    } else { scan = scan + 1 }
                }
            }
        }
    }
    return Ok(ProjectBuilt(project_with_graph(plan, modules, edges)))
}

fn project_graph_acyclic(d: Domain, plan: ProjectPlanRec) -> Result(Bool, __s0_Error) {
    let count = __s0_buffer_len(ProjectModuleRec, plan.modules)
    var indegree = __s0_alloc(U64, d, count + 1)
    var removed = __s0_alloc(U8, d, count + 1)
    var at: U64 = 0
    while at <= count {
        indegree[at] = 0
        removed[at] = 0
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(ProjectEdgeRec, plan.edges) {
        let edge = __s0_buffer_get(ProjectEdgeRec, plan.edges, at)
        if edge.to <= count { indegree[edge.to] = indegree[edge.to] + 1 }
        at = at + 1
    }
    var total: U64 = 0
    var progress = true
    while progress {
        progress = false
        var node: U64 = 1
        while node <= count {
            if removed[node] == 0 && indegree[node] == 0 {
                removed[node] = 1
                total = total + 1
                progress = true
                var edge_at: U64 = 0
                while edge_at < __s0_buffer_len(ProjectEdgeRec, plan.edges) {
                    let edge = __s0_buffer_get(ProjectEdgeRec, plan.edges, edge_at)
                    if edge.from == node && edge.to <= count { indegree[edge.to] = indegree[edge.to] - 1 }
                    edge_at = edge_at + 1
                }
            }
            node = node + 1
        }
    }
    return Ok(total == count)
}

fn project_close_at(d: Domain, plan: ProjectPlanRec, source: U64) -> Result(ProjectBuild, __s0_Error) {
    let count = unsafe c { alderhost_source_count() }
    if source > count {
        if !(try project_graph_acyclic(d, plan)) { return Ok(ProjectRejected(10)) }
        return Ok(ProjectBuilt(plan))
    }
    let scanned = try project_scan_source(d, plan, source)
    return match scanned {
        ProjectRejected(message) => Ok(ProjectRejected(message))
        ProjectBuilt(next) => project_close_at(d, next, source + 1)
    }
}

fn project_close(d: Domain, initial: ProjectPlanRec) -> Result(ProjectBuild, __s0_Error) {
    return project_close_at(d, initial, 1)
}

fn project_seed(plan: ProjectPlanRec) -> ProjectBuild {
    let target = __s0_buffer_get(ProjectTargetRec, plan.targets, plan.selected - 1)
    let requested = project_request(plan, target.root_start, target.root_end)
    if requested == 0 { return ProjectRejected(8) }
    if !unsafe c { alderhost_project_entry_source_set(requested) } { return ProjectRejected(12) }
    return ProjectBuilt(plan)
}

fn project_out_manifest_range(plan: ProjectPlanRec, start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !out(__s0_buffer_get(U8, plan.bytes, at)) { return false }
        at = at + 1
    }
    return true
}

fn project_out_source_path(source: U64) -> Bool {
    var at: U64 = 0
    let end = unsafe c { alderhost_source_path_len(source - 1) }
    while at < end {
        if !out(unsafe c { alderhost_source_path_byte(source - 1, at) }) { return false }
        at = at + 1
    }
    return true
}

fn project_out_source_range(source: U64, start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !out(project_source_byte(source, at)) { return false }
        at = at + 1
    }
    return true
}

fn project_out_triple() -> Bool {
    var at: U64 = 0
    let end = unsafe c { alderhost_triple_len() }
    while at < end {
        if !out(unsafe c { alderhost_triple_byte(at) }) { return false }
        at = at + 1
    }
    return true
}

fn project_byte_u64(byte: U8) -> U64 {
    if byte == 0 { return 0 }
    var result = project_byte_u64(byte / 2) * 2
    if byte % 2 == 1 { result = result + 1 }
    return result
}

fn project_hash_add(a: U64, b: U64) -> U64 {
    let modulus: U64 = 9223372036854775783
    if a >= modulus - b { return a - (modulus - b) }
    return a + b
}

fn project_hash_byte(initial: U64, byte: U8) -> U64 {
    var multiplied = initial
    var bit: U64 = 0
    while bit < 8 {
        multiplied = project_hash_add(multiplied, multiplied)
        bit = bit + 1
    }
    return project_hash_add(project_hash_add(multiplied, initial), project_byte_u64(byte))
}

fn project_snapshot_crc(plan: ProjectPlanRec) -> U64 {
    var crc: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U8, plan.bytes) {
        crc = project_hash_byte(crc, __s0_buffer_get(U8, plan.bytes, at))
        at = at + 1
    }
    var source: U64 = 1
    let count = unsafe c { alderhost_source_count() }
    while source <= count {
        at = 0
        let path_end = unsafe c { alderhost_source_path_len(source - 1) }
        while at < path_end {
            crc = project_hash_byte(crc, unsafe c { alderhost_source_path_byte(source - 1, at) })
            at = at + 1
        }
        crc = project_hash_byte(crc, 0)
        at = 0
        let text_end = unsafe c { alderhost_source_text_len(source - 1) }
        while at < text_end {
            crc = project_hash_byte(crc, project_source_byte(source, at))
            at = at + 1
        }
        source = source + 1
    }
    return crc
}

fn project_source_crc(source: U64) -> U64 {
    var crc: U64 = 0
    var at: U64 = 0
    let end = unsafe c { alderhost_source_text_len(source - 1) }
    while at < end {
        crc = project_hash_byte(crc, project_source_byte(source, at))
        at = at + 1
    }
    return crc
}

// The sysroot identity folds every sysroot source in this build's import
// closure in canonical source order, the same poly64-v1 fold as the package
// snapshot: path bytes, a zero separator, then text bytes per source.
fn project_sysroot_crc() -> U64 {
    var crc: U64 = 0
    var source: U64 = 1
    let count = unsafe c { alderhost_source_count() }
    while source <= count {
        if project_source_is_sysroot(source) {
            var at: U64 = 0
            let path_end = unsafe c { alderhost_source_path_len(source - 1) }
            while at < path_end {
                crc = project_hash_byte(crc, unsafe c { alderhost_source_path_byte(source - 1, at) })
                at = at + 1
            }
            crc = project_hash_byte(crc, 0)
            at = 0
            let text_end = unsafe c { alderhost_source_text_len(source - 1) }
            while at < text_end {
                crc = project_hash_byte(crc, project_source_byte(source, at))
                at = at + 1
            }
        }
        source = source + 1
    }
    return crc
}

fn project_out_hex_digit(value: U64) -> Bool {
    if value < 10 { return out_digit(value) }
    if value == 10 { return out(97) }
    if value == 11 { return out(98) }
    if value == 12 { return out(99) }
    if value == 13 { return out(100) }
    if value == 14 { return out(101) }
    return out(102)
}

fn project_out_hex_u64_at(value: U64, digits: U64) -> Bool {
    if digits > 1 && !project_out_hex_u64_at(value / 16, digits - 1) { return false }
    return project_out_hex_digit(value % 16)
}

fn project_out_hex_u64(value: U64) -> Bool {
    return project_out_hex_u64_at(value, 16)
}

fn project_out_output_path(plan: ProjectPlanRec, target: ProjectTargetRec, kind: U64) -> Bool {
    if !out_string("build/") || !project_out_triple() || !out(47) { return false }
    if plan.profile == 1 { if !out_string("debug/") { return false } }
    else { if !out_string("release/") { return false } }
    if !project_out_manifest_range(plan, plan.package_start, plan.package_end) || !out(47) { return false }
    if kind == 1 {
        return project_out_manifest_range(plan, target.name_start, target.name_end) && out_string(".c")
    }
    if target.kind == 2 && !out_string("lib") { return false }
    if !project_out_manifest_range(plan, target.name_start, target.name_end) { return false }
    if target.kind == 2 { return out_string(".o") }
    return true
}

fn project_module_for_source(plan: ProjectPlanRec, source: U64) -> ProjectModuleRec {
    var at: U64 = 0
    while at < __s0_buffer_len(ProjectModuleRec, plan.modules) {
        let item = __s0_buffer_get(ProjectModuleRec, plan.modules, at)
        if item.source == source { return item }
        at = at + 1
    }
    return ProjectModuleRec(name_start: 0, name_end: 0, source: 0, mark: 0)
}

fn project_range_less(a_source: U64, a_start: U64, a_end: U64, b_source: U64, b_start: U64, b_end: U64) -> Bool {
    var at: U64 = 0
    let an = a_end - a_start
    let bn = b_end - b_start
    while at < an && at < bn {
        let a = project_source_byte(a_source, a_start + at)
        let b = project_source_byte(b_source, b_start + at)
        if a < b { return true }
        if a > b { return false }
        at = at + 1
    }
    return an < bn
}

fn project_edge_less(plan: ProjectPlanRec, a: ProjectEdgeRec, b: ProjectEdgeRec) -> Bool {
    let am = project_module_for_source(plan, a.from)
    let bm = project_module_for_source(plan, b.from)
    if project_range_less(am.source, am.name_start, am.name_end, bm.source, bm.name_start, bm.name_end) { return true }
    if project_range_less(bm.source, bm.name_start, bm.name_end, am.source, am.name_start, am.name_end) { return false }
    return project_range_less(a.from, a.name_start, a.name_end, b.from, b.name_start, b.name_end)
}

fn project_emit_plan(plan: ProjectPlanRec) -> Bool {
    let target = __s0_buffer_get(ProjectTargetRec, plan.targets, plan.selected - 1)
    if !out_string("ALDER-BUILD-PLAN 1\nedition 1\ntarget ") || !project_out_manifest_range(plan, target.name_start, target.name_end) { return false }
    if target.kind == 1 { if !out_string("\nkind bin") { return false } }
    else { if !out_string("\nkind lib") { return false } }
    if plan.profile == 1 { if !out_string("\nprofile debug") { return false } }
    else { if !out_string("\nprofile release") { return false } }
    if !out_string("\ntriple ") || !project_out_triple() || !out_string("\ntoolchain system-cc-c11\nflags strict-c11,") { return false }
    if plan.profile == 1 { if !out_string("O0") { return false } }
    else { if !out_string("O2") { return false } }
    if !out_string("\nsysroot v1:") || !project_out_hex_u64(project_sysroot_crc()) || !out_string("\nsnapshot poly64-v1:") || !project_out_hex_u64(project_snapshot_crc(plan)) || !out_string("\npackage ") || !project_out_manifest_range(plan, plan.package_start, plan.package_end) || !out(10) { return false }
    if !out_string("root ") || !project_out_manifest_range(plan, target.root_start, target.root_end) || !out_string("\noutput c ") || !project_out_output_path(plan, target, 1) { return false }
    if target.kind == 1 { if !out_string("\noutput executable ") { return false } }
    else { if !out_string("\noutput object ") { return false } }
    if !project_out_output_path(plan, target, 2) || !out(10) { return false }
    var source: U64 = 1
    let count = unsafe c { alderhost_source_count() }
    while source <= count {
        let module_rec = project_module_for_source(plan, source)
        if !out_string("source ") || !project_out_source_path(source) || !out_string(" bytes ") || !out_u64(unsafe c { alderhost_source_text_len(source - 1) }) || !out_string(" poly64-v1:") || !project_out_hex_u64(project_source_crc(source)) || !out_string(" module ") || !project_out_source_range(module_rec.source, module_rec.name_start, module_rec.name_end) || !out(10) { return false }
        source = source + 1
    }
    var rank: U64 = 0
    let edge_count = __s0_buffer_len(ProjectEdgeRec, plan.edges)
    while rank < edge_count {
        var candidate: U64 = 0
        var at: U64 = 0
        while at < edge_count {
            let edge = __s0_buffer_get(ProjectEdgeRec, plan.edges, at)
            var before: U64 = 0
            var other: U64 = 0
            while other < edge_count {
                if project_edge_less(plan, __s0_buffer_get(ProjectEdgeRec, plan.edges, other), edge) { before = before + 1 }
                other = other + 1
            }
            if before == rank { candidate = at + 1 }
            at = at + 1
        }
        if candidate == 0 { return false }
        let edge = __s0_buffer_get(ProjectEdgeRec, plan.edges, candidate - 1)
        let module_rec = project_module_for_source(plan, edge.from)
        if !out_string("edge ") || !project_out_source_range(module_rec.source, module_rec.name_start, module_rec.name_end) || !out_string(" -> ") || !project_out_source_range(edge.from, edge.name_start, edge.name_end) || !out(10) { return false }
        rank = rank + 1
    }
    return true
}

fn project_emit_plan_response(plan: ProjectPlanRec) -> Bool {
    if !driver_json() { return project_emit_plan(plan) }
    if !driver_select(0) || !out_string("{\"version\":1,\"command\":\"test-plan\",\"success\":true,\"diagnostics\":[],\"artifact\":{\"kind\":\"build-plan\",\"content\":\"") || !driver_select(2) { return false }
    if !project_emit_plan(plan) { return false }
    return driver_select(0) && out_string("\"}}\n")
}

fn project_host_output_byte(byte: U8) -> Bool {
    return unsafe c { alderhost_project_output_byte(byte) }
}

fn project_host_output_string(word: __s0_String) -> Bool {
    var at: U64 = 0
    while at < len(word) {
        if !project_host_output_byte(word[at]) { return false }
        at = at + 1
    }
    return true
}

fn project_host_output_range(plan: ProjectPlanRec, start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !project_host_output_byte(__s0_buffer_get(U8, plan.bytes, at)) { return false }
        at = at + 1
    }
    return true
}

fn project_host_output_triple() -> Bool {
    var at: U64 = 0
    let end = unsafe c { alderhost_triple_len() }
    while at < end {
        if !project_host_output_byte(unsafe c { alderhost_triple_byte(at) }) { return false }
        at = at + 1
    }
    return true
}

fn project_configure_one_output(plan: ProjectPlanRec, target: ProjectTargetRec, kind: U64) -> Bool {
    if !unsafe c { alderhost_project_output_reset(kind) } { return false }
    if !project_host_output_string("build/") || !project_host_output_triple() || !project_host_output_byte(47) { return false }
    if plan.profile == 1 { if !project_host_output_string("debug/") { return false } }
    else { if !project_host_output_string("release/") { return false } }
    if !project_host_output_range(plan, plan.package_start, plan.package_end) || !project_host_output_byte(47) { return false }
    if kind == 1 {
        if !project_host_output_range(plan, target.name_start, target.name_end) || !project_host_output_string(".c") { return false }
    } else {
        if target.kind == 2 && !project_host_output_string("lib") { return false }
        if !project_host_output_range(plan, target.name_start, target.name_end) { return false }
        if target.kind == 2 && !project_host_output_string(".o") { return false }
    }
    return unsafe c { alderhost_project_output_finish() }
}

fn project_configure_outputs(plan: ProjectPlanRec) -> Bool {
    let target = __s0_buffer_get(ProjectTargetRec, plan.targets, plan.selected - 1)
    if plan.action == 3 && target.kind != 1 { return false }
    if !unsafe c { alderhost_project_target_kind(target.kind) } { return false }
    return project_configure_one_output(plan, target, 1) && project_configure_one_output(plan, target, 2)
}

fn project_compile_closed(d: Domain, plan: ProjectPlanRec) -> I32 {
    if plan.action == 4 {
        if !project_emit_plan_response(plan) { return driver_failure(3, "io", "cannot write build plan") }
        return 0
    }
    if (plan.action == 2 || plan.action == 3) && !project_configure_outputs(plan) { return project_fail(12) }
    if plan.action != 4 && !project_prepare_error_prelude() { return project_fail(12) }
    if plan.action != 4 && !project_prepare_entry_wrapper(plan) { return project_fail(12) }
    return project_compile_prepared(d)
}

fn project_reclose_sorted(d: Domain, plan: ProjectPlanRec) -> I32 {
    return match project_parse_manifest(d, plan.bytes) {
        Err(error) => project_fail(12)
        Ok(parsed) => match parsed {
            ProjectRejected(message) => project_fail(message)
            ProjectBuilt(reparsed) => match project_seed(reparsed) {
                ProjectRejected(message) => project_fail(message)
                ProjectBuilt(ready) => match project_close(d, ready) {
                    Err(error) => project_fail(12)
                    Ok(closed) => match closed {
                        ProjectRejected(message) => project_fail(message)
                        ProjectBuilt(complete) => project_compile_closed(d, complete)
                    }
                }
            }
        }
    }
}

fn project_sort_and_reclose(d: Domain, plan: ProjectPlanRec) -> I32 {
    if !unsafe c { alderhost_sources_sort() } { return project_fail(12) }
    return project_reclose_sorted(d, plan)
}

fn project_prepare(d: Domain) -> I32 {
    return match project_copy_manifest(d) {
        Err(error) => project_fail(12)
        Ok(bytes) => match project_parse_manifest(d, bytes) {
            Err(error) => project_fail(12)
            Ok(parsed) => match parsed {
                ProjectRejected(message) => project_fail(message)
                ProjectBuilt(plan) => match project_seed(plan) {
                    ProjectRejected(message) => project_fail(message)
                    ProjectBuilt(ready) => match project_close(d, ready) {
                        Err(error) => project_fail(12)
                        Ok(closed) => match closed {
                            ProjectRejected(message) => project_fail(message)
                            ProjectBuilt(complete) => project_sort_and_reclose(d, complete)
                        }
                    }
                }
            }
        }
    }
}
