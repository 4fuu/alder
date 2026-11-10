module std.path

// The Milestone 8 lexical path foundation: the shared exact-bytes host
// string `OsString`, the checked `Path` value, and purely lexical operations
// over both. Public snapshot v1 (docs/api/std.path-v1.md) fixes the surface;
// this module implements the POSIX-native v1 rules: `/` separates, `.` and
// `..` are ordinary components, and one leading `/` is the root. Repeated
// separators collapse, a trailing separator is not a component, and stored
// bytes keep exactly what construction accepted. Nothing here opens, stats,
// or normalizes through the filesystem; every operation is total,
// deterministic, and independent of host state, locale, and enumeration
// order.

/// One owned exact host string: the bytes are precisely what the host gave
/// or will receive, with no encoding assumption. Interior NUL bytes are
/// rejected at construction because no host interface can carry them.
/// Equality is exact bytes. This is the one host-string type the hosted
/// modules share; `std.env`, `std.io`, and `std.process` convert to and
/// from it explicitly and nothing reinterprets its bytes as text.
pub type OsString {
    data: Bytes
}

/// One owned, checked path value. The bytes are exactly the host path:
/// interior NUL bytes are rejected at construction because no target can
/// address them. Paths compare by exact bytes.
pub type Path {
    data: OsString
}

/// Failure of host-string or path construction from text: the only
/// rejected byte is interior NUL.
pub enum PathError {
    /// The input contained an interior NUL byte.
    InvalidEncoding
}

/// One component of a path in native form.
pub enum Component {
    /// The leading root, `/` on POSIX targets.
    RootDir
    /// A `.` component.
    CurDir
    /// A `..` component.
    ParentDir
    /// A normal component's exact bytes.
    Normal(name: OsString)
}

impl OsString {
    /// Checks text as a host string.
    fn parse(text: String) -> Result(OsString, PathError) {
        return OsString.from_bytes(text.to_bytes())
    }

    /// Builds from owned bytes, rejecting interior NUL bytes.
    fn from_bytes(data: Bytes) -> Result(OsString, PathError) {
        if bytes_have_nul(data) {
            return Err(InvalidEncoding)
        }
        return Ok(OsString(data: data))
    }

    /// The exact bytes.
    fn to_bytes(self) -> Bytes {
        return self.data
    }

    /// The text when the bytes are valid UTF-8, `None` otherwise.
    /// Non-text host strings are a representable state, not an error.
    fn to_string(self) -> Option(String) {
        return self.data.to_string_checked()
    }

    /// The byte length.
    fn len(self) -> U64 {
        return self.data.len()
    }
}

impl Path {
    /// Checks text as a path: every UTF-8 sequence is accepted except one
    /// containing an interior NUL byte.
    fn parse(text: String) -> Result(Path, PathError) {
        var out: Result(Path, PathError) = Err(InvalidEncoding)
        match OsString.parse(text) {
            Ok(name) => { out = Ok(Path(data: name)) }
            Err(failure) => { out = Err(failure) }
        }
        return out
    }

    /// Builds a path from host bytes. Infallible: `OsString` already
    /// rejects interior NUL bytes.
    fn from_os(name: OsString) -> Path {
        return Path(data: name)
    }

    /// The exact bytes as an `OsString`.
    fn to_os(self) -> OsString {
        return self.data
    }

    /// The bytes as text when they are valid UTF-8, `None` otherwise.
    /// Non-text paths are a representable state, not an error.
    fn to_string(self) -> Option(String) {
        return self.data.to_string()
    }

    /// The path's components in native form: one `RootDir` for any run of
    /// leading separators, then every nonempty segment in order. A trailing
    /// separator produces no component.
    fn components(self) -> Vec(Component) {
        var out: Vec(Component) = Vec.new(Component)
        let raw = self.data.data
        let size = raw.len()
        if size == 0 {
            return out
        }
        if raw.byte(0) == 47 {
            out.push(RootDir)
        }
        var at: U64 = 0
        var segment: U64 = 0
        while at <= size {
            var boundary: Bool = false
            if at == size {
                boundary = true
            } else if raw.byte(at) == 47 {
                boundary = true
            }
            if boundary {
                if at > segment {
                    match segment_kind(raw, segment, at) {
                        Dot => { out.push(CurDir) }
                        DotDot => { out.push(ParentDir) }
                        Plain => {
                            match OsString.from_bytes(raw.slice(segment, at)) {
                                Ok(name) => { out.push(Normal(name)) }
                                Err(_) => {}
                            }
                        }
                    }
                }
                segment = at + 1
            }
            at = at + 1
        }
        return out
    }

    /// Lexical join. An empty suffix returns the path unchanged; an
    /// absolute suffix replaces the path. Never consults the filesystem.
    fn join(self, suffix: Path) -> Path {
        let suffix_parts = suffix.components()
        if suffix_parts.len() == 0 {
            return Path(data: self.data)
        }
        if suffix.is_absolute() {
            return Path(data: suffix.data)
        }
        var all: Vec(Component) = Vec.new(Component)
        let mine = self.components()
        var at: U64 = 0
        while at < mine.len() {
            all.push(mine[at])
            at = at + 1
        }
        at = 0
        while at < suffix_parts.len() {
            all.push(suffix_parts[at])
            at = at + 1
        }
        return Path(data: OsString(data: render_parts(all)))
    }

    /// Collapses `.` components and resolves `..` lexically. A `..` that
    /// would climb past the root is kept, so normalization never needs the
    /// filesystem and never turns a relative path into an absolute one.
    fn normalize(self) -> Path {
        let raw = self.components()
        var out: Vec(Component) = Vec.new(Component)
        var at: U64 = 0
        while at < raw.len() {
            match raw[at] {
                RootDir => { out.push(RootDir) }
                CurDir => {}
                ParentDir => {
                    var popped: Bool = false
                    if out.len() > 0 {
                        match out[out.len() - 1] {
                            Normal(_) => { popped = true }
                            RootDir => {}
                            CurDir => {}
                            ParentDir => {}
                        }
                    }
                    if popped {
                        var trimmed: Vec(Component) = Vec.new(Component)
                        var copy_at: U64 = 0
                        while copy_at + 1 < out.len() {
                            trimmed.push(out[copy_at])
                            copy_at = copy_at + 1
                        }
                        out = trimmed
                    } else {
                        out.push(ParentDir)
                    }
                }
                Normal(name) => { out.push(Normal(name)) }
            }
            at = at + 1
        }
        return Path(data: OsString(data: render_parts(out)))
    }

    /// The final normal component, `None` when the path ends in a root,
    /// `.`/`..` component, or is empty.
    fn file_name(self) -> Option(OsString) {
        let parts = self.components()
        let size = parts.len()
        var out: Option(OsString) = None
        if size > 0 {
            match parts[size - 1] {
                Normal(name) => { out = Some(name) }
                RootDir => {}
                CurDir => {}
                ParentDir => {}
            }
        }
        return out
    }

    /// `file_name` without its final extension, `None` when there is no
    /// file name.
    fn file_stem(self) -> Option(OsString) {
        var out: Option(OsString) = None
        match self.file_name() {
            Some(name) => {
                let raw = name.data
                let size = raw.len()
                var dot: U64 = size
                var scan: U64 = 1
                while scan < size {
                    if raw.byte(scan) == 46 {
                        dot = scan
                    }
                    scan = scan + 1
                }
                if dot < size {
                    out = Some(OsString(data: raw.slice(0, dot)))
                } else {
                    out = Some(name)
                }
            }
            None => {}
        }
        return out
    }

    /// The final extension's bytes without the dot, `None` when the file
    /// name has no extension or is a dotfile with none. A trailing dot
    /// yields the empty extension.
    fn extension(self) -> Option(OsString) {
        var out: Option(OsString) = None
        match self.file_name() {
            Some(name) => {
                let raw = name.data
                let size = raw.len()
                var dot: U64 = size
                var scan: U64 = 1
                while scan < size {
                    if raw.byte(scan) == 46 {
                        dot = scan
                    }
                    scan = scan + 1
                }
                if dot < size {
                    out = Some(OsString(data: raw.slice(dot + 1, size)))
                }
            }
            None => {}
        }
        return out
    }

    /// The path without its final component, `None` at the root or for an
    /// empty path. The remainder of a one-component path is the empty path.
    fn parent(self) -> Option(Path) {
        let parts = self.components()
        let size = parts.len()
        if size == 0 {
            return None
        }
        if size == 1 {
            var only_root: Bool = false
            match parts[0] {
                RootDir => { only_root = true }
                CurDir => {}
                ParentDir => {}
                Normal(_) => {}
            }
            if only_root {
                return None
            }
        }
        var rest: Vec(Component) = Vec.new(Component)
        var at: U64 = 0
        while at + 1 < size {
            rest.push(parts[at])
            at = at + 1
        }
        return Some(Path(data: OsString(data: render_parts(rest))))
    }

    /// True when the first component is the root.
    fn is_absolute(self) -> Bool {
        let raw = self.data.data
        if raw.len() == 0 {
            return false
        }
        return raw.byte(0) == 47
    }
}

// Reports whether the bytes contain an interior NUL byte.
fn bytes_have_nul(data: Bytes) -> Bool {
    var at: U64 = 0
    while at < data.len() {
        if data.byte(at) == 0 {
            return true
        }
        at = at + 1
    }
    return false
}

// Classifies one segment between separators without allocating; the
// components() loop constructs any OsString itself, in its own frame.
enum SegmentKind {
    Dot
    DotDot
    Plain
}

fn segment_kind(raw: Bytes, lo: U64, hi: U64) -> SegmentKind {
    let width = hi - lo
    if width == 1 {
        if raw.byte(lo) == 46 {
            return Dot
        }
    } else if width == 2 {
        if raw.byte(lo) == 46 {
            if raw.byte(lo + 1) == 46 {
                return DotDot
            }
        }
    }
    return Plain
}

// Renders components back to exact path bytes: one slash between neighbors,
// the root fusing with what follows it, and no trailing slash.
fn render_parts(parts: Vec(Component)) -> Bytes {
    let nothing = ""
    var out: Bytes = nothing.to_bytes()
    let size = parts.len()
    if size == 0 {
        return out
    }
    var at: U64 = 0
    var need_slash: Bool = false
    match parts[0] {
        RootDir => {
            let slash = "/"
            out = slash.to_bytes()
            at = 1
        }
        CurDir => {}
        ParentDir => {}
        Normal(_) => {}
    }
    while at < size {
        if need_slash {
            let slash = "/"
            out = out.concat(slash.to_bytes())
        }
        out = out.concat(render_one(parts[at]))
        need_slash = true
        at = at + 1
    }
    return out
}

// Renders one component's bytes.
fn render_one(part: Component) -> Bytes {
    var out: Bytes = empty_bytes()
    match part {
        RootDir => {
            let raw = "/"
            out = raw.to_bytes()
        }
        CurDir => {
            let raw = "."
            out = raw.to_bytes()
        }
        ParentDir => {
            let raw = ".."
            out = raw.to_bytes()
        }
        Normal(name) => {
            out = name.data
        }
    }
    return out
}

// The empty byte sequence.
fn empty_bytes() -> Bytes {
    let nothing = ""
    return nothing.to_bytes()
}
