module hello.std_format_example

import core.format as core_format
import std.format as fmt

// The executable std.format v1 snapshot example. The expected text exercises
// integer, general float, fixed float, and F32 rendering in one builder.

pub fn std_format_example() -> U64 {
    let plain = core_format.FormatSpec.plain()
    var fixed = core_format.FormatSpec.plain()
    fixed.precision = Some(2)
    fixed.kind = core_format.FormatKind.Fixed

    var f = fmt.Formatter.new()
    f.text("n=")
    f.i64(-7, plain)
    f.text(" f=")
    f.f64(0.1, plain)
    f.text(" g=")
    f.f64(1.5, fixed)
    f.text(" h=")
    f.f32(0.5, plain)

    var result: U64 = 0
    match f.finish() {
        Ok(text) => {
            if text == "n=-7 f=0.1 g=1.50 h=0.5" { result = 1 }
        }
        Err(_) => {}
    }
    return result
}
