package frontend

import (
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
	"github.com/4fuu/aster/mir/verify"
)

func compileStr(t *testing.T, src string) *mir.Module {
	t.Helper()
	m, err := Compile(src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}
	if errs := verify.Module(m); len(errs) > 0 {
		t.Fatalf("lowered MIR failed verification:\n%s", verify.Errors(errs).String())
	}
	return m
}

// TestSmokeBasic compiles a small program through the whole pipeline.
func TestSmokeBasic(t *testing.T) {
	src := `
fn add(a: I64, b: I64) -> I64 {
    return a + b;
}

fn main() -> I32 {
    let x = add(20, 22);
    if x != 42 {
        return 1;
    }
    return 0;
}
`
	m := compileStr(t, src)
	if len(m.Functions) != 2 {
		t.Fatalf("expected 2 functions, got %d", len(m.Functions))
	}
	out := mir.Print(m)
	if !strings.Contains(out, "fn @add") || !strings.Contains(out, "int.add.checked") {
		t.Fatalf("unexpected MIR:\n%s", out)
	}
}

// TestSmokeStructEnum exercises structs, enums, and match.
func TestSmokeStructEnum(t *testing.T) {
	src := `
type Point { x: I64, y: I64 }

enum Shape {
    Circle(I64),
    Dot,
}

fn area(s: Shape) -> I64 {
    return match s {
        Circle(r) => r * r,
        Dot => 0,
    };
}

fn main() -> I32 {
    let p = Point(3, 4);
    if p.x + p.y != 7 {
        return 1;
    }
    if area(Circle(5)) != 25 {
        return 2;
    }
    if area(Dot) != 0 {
        return 3;
    }
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeOptionResult exercises Option/Result and try.
func TestSmokeOptionResult(t *testing.T) {
	src := `
fn half(n: I64) -> Option(I64) {
    if n % 2 == 0 {
        return Some(n / 2);
    }
    return None;
}

fn checked(n: I64, d: I64) -> Result(I64, I64) {
    if d == 0 {
        return Err(1);
    }
    return Ok(n / d);
}

fn propagate(d: I64) -> Result(I64, I64) {
    let q = try checked(10, d);
    return Ok(q);
}

fn main() -> I32 {
    let h = half(8);
    if match h {
        Some(v) => v,
        None => 0,
    } != 4 {
        return 1;
    }
    let p = propagate(0);
    if match p {
        Ok(v) => v,
        Err(e) => e,
    } != 1 {
        return 2;
    }
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeDomainSlice exercises domains, alloc, and slices.
func TestSmokeDomainSlice(t *testing.T) {
	src := `
fn fill(d: Domain, n: U64) -> I64 {
    let buf = Alloc(I64, d, n);
    var i: U64 = 0;
    while i < n {
        buf[i] = 3;
        i = i + 1;
    }
    return buf[0];
}

fn main(d: Domain) -> I32 {
    let v = fill(d, 4);
    if v != 3 {
        return 1;
    }
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeGeneric exercises generic functions and inference.
func TestSmokeGeneric(t *testing.T) {
	src := `
fn identity(T: type, x: T) -> T {
    return x;
}

fn twice(A: type, x: A, y: A) -> A {
    return x;
}

fn main() -> I32 {
    if identity(7) != 7 {
        return 1;
    }
    if identity(I64, 8) != 8 {
        return 2;
    }
    if twice(1, 2) != 1 {
        return 3;
    }
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeMap exercises map construction and lookups.
func TestSmokeMap(t *testing.T) {
	src := `
fn main(d: Domain) -> I32 {
    var m = Map(U64, I64)(d);
    Set(m, 1, 100);
    Set(m, 2, 200);
    let a = Get(m, 1);
    if match a {
        Some(v) => v,
        None => 0,
    } != 100 {
        return 1;
    }
    let b = Get(m, 3);
    if match b {
        Some(v) => v,
        None => 0,
    } != 0 {
        return 2;
    }
    let r = Remove(m, 2);
    if !r {
        return 3;
    }
    let c = Get(m, 2);
    if match c {
        Some(v) => v,
        None => 1,
    } != 1 {
        return 4;
    }
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeCleanup exercises scoped cleanup with an observable side effect.
func TestSmokeCleanup(t *testing.T) {
	src := `
import c counter: fn(I64) -> Unit

fn close(x: I64) -> Unit {
    counter(x);
}

fn main() -> I32 {
    using h = 5 with close;
    return 0;
}
`
	compileStr(t, src)
}

// TestSmokeString exercises string literals and iteration.
func TestSmokeString(t *testing.T) {
	src := `
fn main() -> I32 {
    let s = "hello";
    if len(s) != 5 {
        return 1;
    }
    if s[1] != 101 {
        return 2;
    }
    var sum: U64 = 0;
    for c in s {
        sum = sum + 1;
    }
    if sum != 5 {
        return 3;
    }
    let tail = range(s, 1, 3);
    if len(tail) != 2 {
        return 4;
    }
    return 0;
}
`
	compileStr(t, src)
}
