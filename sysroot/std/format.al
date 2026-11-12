module std.format

import core.format
import std.text { StringBuilder }

import c "std/c/format_shim.h" as cformat {
    raw fn float64 = "format_f64"(value: c.Double, precision: c.Int, style: c.Int, out: c.Ptr(c.UChar), capacity: c.Size) -> c.Int
    raw fn float32 = "format_f32"(value: c.Float, precision: c.Int, style: c.Int, out: c.Ptr(c.UChar), capacity: c.Size) -> c.Int
}

// The hosted formatter builds a String with std.text's StringBuilder. Integer
// and text formatting stay in core.format; float spelling goes through the
// audited format_shim.h shortest-round-trip helper. Push methods record the
// first FormatError and finish reports it after the builder is released.

/// A value-semantic formatting builder. `new` starts empty; push methods
/// append in call order and `finish` consumes the builder.
pub type Formatter {
    builder: StringBuilder
    error: Option(format.FormatError)
}

impl Formatter {
    fn new() -> Formatter {
        return Formatter(builder: StringBuilder.new(), error: None)
    }

    fn text(mut self, value: String) -> Unit {
        self.builder = self.builder.push_text(value)
        return
    }

    fn display(T: type(Display), mut self, value: T, spec: format.FormatSpec) -> Unit {
        match format.pad(value.display(), spec) {
            Ok(text) => { self.builder = self.builder.push_text(text) }
            Err(failure) => { self.remember(failure) }
        }
        return
    }

    fn i64(mut self, value: I64, spec: format.FormatSpec) -> Unit {
        match format.format_i64(value, spec) {
            Ok(text) => { self.builder = self.builder.push_text(text) }
            Err(failure) => { self.remember(failure) }
        }
        return
    }

    fn u64(mut self, value: U64, spec: format.FormatSpec) -> Unit {
        match format.format_u64(value, spec) {
            Ok(text) => { self.builder = self.builder.push_text(text) }
            Err(failure) => { self.remember(failure) }
        }
        return
    }

    fn f64(mut self, value: F64, spec: format.FormatSpec) -> Unit {
        match format_float64(value, spec) {
            Ok(text) => { self.builder = self.builder.push_text(text) }
            Err(failure) => { self.remember(failure) }
        }
        return
    }

    fn f32(mut self, value: F32, spec: format.FormatSpec) -> Unit {
        match format_float32(value, spec) {
            Ok(text) => { self.builder = self.builder.push_text(text) }
            Err(failure) => { self.remember(failure) }
        }
        return
    }

    fn finish(self) -> Result(String, format.FormatError) {
        match self.error {
            Some(failure) => { return Err(failure) }
            None => {}
        }
        return Ok(self.builder.finish())
    }

    fn remember(mut self, failure: format.FormatError) -> Unit {
        match self.error {
            Some(_) => {}
            None => { self.error = Some(failure) }
        }
        return
    }
}

fn zeroed(size: U64) -> Vec(U8) {
    var room: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < size {
        room.push(0)
        at = at + 1
    }
    return room
}

fn ascii_string(data: Vec(U8)) -> Result(String, format.FormatError) {
    let size = data.len()
    return match data.slice(0, size).to_bytes().to_string_checked() {
        Some(text) => Ok(text)
        None => Err(format.FormatError.Unsupported)
    }
}

fn float_style(spec: format.FormatSpec) -> Result(I32, format.FormatError) {
    if spec.alternate { return Err(format.FormatError.Unsupported) }
    if spec.kind == format.FormatKind.Default || spec.kind == format.FormatKind.General { return Ok(0) }
    if spec.kind == format.FormatKind.Fixed { return Ok(1) }
    if spec.kind == format.FormatKind.Scientific { return Ok(2) }
    return Err(format.FormatError.InvalidKind)
}

fn float_precision(spec: format.FormatSpec) -> Result(I32, format.FormatError) {
    if spec.kind == format.FormatKind.Default || spec.kind == format.FormatKind.General {
        match spec.precision {
            Some(_) => { return Err(format.FormatError.Unsupported) }
            None => {}
        }
        return Ok(-1)
    }
    var precision: I32 = 6
    match spec.precision {
        Some(value) => {
            if value > 64 { return Err(format.FormatError.Unsupported) }
            precision = value.to_i32_wrapping()
        }
        None => {}
    }
    return Ok(precision)
}

fn float_sign(text: String, spec: format.FormatSpec) -> String {
    if text.len() > 0 && text.byte(0) == 45 { return text }
    if text.len() > 0 && text.byte(0) == 43 { return text }
    if text.len() > 0 && text.byte(0) == 32 { return text }
    if spec.sign == format.Sign.Plus { return "+".concat(text) }
    if spec.sign == format.Sign.Space { return " ".concat(text) }
    return text
}

fn pad_float(text: String, spec: format.FormatSpec) -> Result(String, format.FormatError) {
    if spec.zero_pad && spec.align == format.Align.Right {
        let size = text.len()
        if spec.width <= size { return Ok(text) }
        var sign_text: String = ""
        var rest = text
        let first = text.byte(0)
        if first == 45 || first == 43 || first == 32 {
            sign_text = match text.slice(0, 1).to_bytes().to_string_checked() {
                Some(value) => value
                None => ""
            }
            rest = match text.slice(1, size).to_bytes().to_string_checked() {
                Some(value) => value
                None => ""
            }
        }
        var zeros = spec.width - size
        var fill: String = ""
        while zeros > 0 {
            fill = fill.concat("0")
            zeros = zeros - 1
        }
        return Ok(sign_text.concat(fill).concat(rest))
    }
    return format.pad(text, spec)
}

fn format_float64(value: F64, spec: format.FormatSpec) -> Result(String, format.FormatError) {
    let style = try float_style(spec)
    let precision = try float_precision(spec)
    let capacity: U64 = 256
    var room = zeroed(capacity)
    let raw_length = unsafe c { cformat.float64(value.to_c_double(), precision.to_c_int(), style.to_c_int(), room.slice_mut(0, capacity), capacity.to_c_size()) }
    let length = raw_length.to_i32()
    if length < 0 { return Err(format.FormatError.Unsupported) }
    let size = length.to_u64_wrapping()
    var raw: String = ""
    match room.slice(0, size).to_bytes().to_string_checked() {
        Some(text) => { raw = text }
        None => { return Err(format.FormatError.Unsupported) }
    }
    return pad_float(float_sign(raw, spec), spec)
}

fn format_float32(value: F32, spec: format.FormatSpec) -> Result(String, format.FormatError) {
    let style = try float_style(spec)
    let precision = try float_precision(spec)
    let capacity: U64 = 256
    var room = zeroed(capacity)
    let raw_length = unsafe c { cformat.float32(value.to_c_float(), precision.to_c_int(), style.to_c_int(), room.slice_mut(0, capacity), capacity.to_c_size()) }
    let length = raw_length.to_i32()
    if length < 0 { return Err(format.FormatError.Unsupported) }
    let size = length.to_u64_wrapping()
    var raw: String = ""
    match room.slice(0, size).to_bytes().to_string_checked() {
        Some(text) => { raw = text }
        None => { return Err(format.FormatError.Unsupported) }
    }
    return pad_float(float_sign(raw, spec), spec)
}
