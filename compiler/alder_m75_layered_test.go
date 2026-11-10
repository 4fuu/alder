package compiler

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The M7.5 exit item: a compiler-scale layered DAG over traits, constraints,
// generics, and closures. One generic trait with a defaulted method is
// implemented by many record types, and a stack of constrained generic
// layers instantiates itself two ways (layer i calls layer i+1 and i+2), so
// monomorphization walks a DAG of 8 x 32 instances rather than a chain.
// Closures appear at the concrete level, where main snapshots a local into a
// closure and threads it through a function-typed helper, and inside generic
// bodies, where each instance materializes its own thunk: a generic layer
// snapshots a U64 seed at two cell instantiations, and keep_value snapshots a
// value of the type parameter itself at U64 and at a record type. The program
// must terminate with identical diagnostics, MIR, and C across processes and
// across source permutations, and the generated C must run under strict C11.
//
// The generator stays inside the fn-value envelope the compiler supports:
// named function values and closures mix freely and thread through
// constrained generic calls and function-typed helpers, and closures inside
// generic bodies carry only snapshot-copyable captures.
const (
	m75LayeredCells  = 8
	m75LayeredDepth  = 32
	m75LayeredSplits = 3
)

// m75LayeredDeclarations builds every top-level declaration as its own
// string so the program splits and recombines at declaration boundaries.
func m75LayeredDeclarations() (declarations []string, want []uint64) {
	declarations = append(declarations, "trait Deliver(Out: type) {\n    fn deliver(self) -> Out\n    fn twice(self) -> Out {\n        return self.deliver()\n    }\n}")
	declarations = append(declarations, "fn twice_apply(f: fn(U64) -> U64, v: U64) -> U64 {\n    return f(f(v))\n}")
	declarations = append(declarations, "fn scale(x: U64) -> U64 { return x + 1 }")
	// Closures inside generic bodies: each instance materializes its own
	// thunk, one capturing a U64 seed and one capturing a value of the type
	// parameter itself.
	declarations = append(declarations, "fn rebased_layer(P: type, p: P, seed: U64) -> U64\nwhere P: Deliver(U64) {\n    let rebased = fn(x: U64) => x + seed\n    return rebased(p.deliver())\n}")
	declarations = append(declarations, "fn keep_value(T: type, value: T) -> T {\n    let same = fn() -> T { return value }\n    return same()\n}")
	// Nested closure literals: the inner literal reads the generic layer's
	// seed, which the outer literal never reads itself, so the outer
	// environment must carry the transitive capture. The outer environment
	// records the domain it lives in and the thunk allocates the inner
	// environment beside it.
	declarations = append(declarations, "fn nested_layer(T: type, seed: U64) -> U64 {\n    let outer = fn() -> fn(U64) -> U64 {\n        let inner = fn(x: U64) -> U64 { return x + seed }\n        return inner\n    }\n    let made = outer()\n    return made(seed)\n}")
	for cell := 0; cell < m75LayeredCells; cell++ {
		declarations = append(declarations, fmt.Sprintf("type Cell%03d {\n    v: U64\n}", cell))
		declarations = append(declarations, fmt.Sprintf("impl Deliver(U64) for Cell%03d {\n    fn deliver(self) -> U64 { return self.v }\n}", cell))
	}
	for i := 0; i < m75LayeredDepth; i++ {
		var layer strings.Builder
		layer.WriteString(fmt.Sprintf("fn layer_%03d(P: type, p: P, seed: U64) -> U64\nwhere P: Deliver(U64) {\n", i))
		if i == m75LayeredDepth-1 {
			layer.WriteString("    return seed + p.twice()\n")
		} else {
			if i+2 <= m75LayeredDepth-1 {
				layer.WriteString(fmt.Sprintf("    if seed %% 8 == 0 { return layer_%03d(P, p, seed + 2) }\n", i+2))
			}
			layer.WriteString(fmt.Sprintf("    return layer_%03d(P, p, seed + 1)\n", i+1))
		}
		layer.WriteString("}")
		declarations = append(declarations, layer.String())
	}
	// The expected leaf results come from the mirrored path below; the
	// second call wraps the DAG result in a main-level closure and the
	// third threads that closure through the function-typed helper.
	want = append(want, m75LayeredLeaf(0), m75LayeredLeaf(7*10)+5, m75LayeredLeaf(3*10)+2)
	var main strings.Builder
	main.WriteString("fn main() -> I32 {\n")
	main.WriteString(fmt.Sprintf("    if layer_000(Cell000, Cell000(v: 0), 0) != %d { return 1 }\n", want[0]))
	main.WriteString("    let offset: U64 = 5\n    let shifted = fn(x: U64) => x + offset\n")
	main.WriteString(fmt.Sprintf("    if shifted(layer_000(Cell007, Cell007(v: 70), 0)) != %d { return 2 }\n", want[1]))
	main.WriteString("    if twice_apply(shifted, 1) != 11 { return 3 }\n")
	main.WriteString(fmt.Sprintf("    if twice_apply(scale, layer_000(Cell003, Cell003(v: 30), 0)) != %d { return 4 }\n", want[2]))
	main.WriteString("    if rebased_layer(Cell001, Cell001(v: 10), 5) != 15 { return 5 }\n")
	main.WriteString("    if rebased_layer(Cell002, Cell002(v: 20), 7) != 27 { return 6 }\n")
	main.WriteString("    if keep_value(U64, 9) != 9 { return 7 }\n")
	main.WriteString("    if keep_value(Cell004, Cell004(v: 44)).v != 44 { return 8 }\n")
	main.WriteString("    if nested_layer(U64, 6) != 12 { return 10 }\n")
	main.WriteString("    if nested_layer(Cell006, 7) != 14 { return 11 }\n")
	main.WriteString("    if Cell005(v: 50).twice() != 50 { return 9 }\n    return 0\n}")
	declarations = append(declarations, main.String())
	return declarations, want
}

func m75LayeredDagProgram() (string, []uint64) {
	declarations, want := m75LayeredDeclarations()
	return strings.Join(declarations, "\n\n") + "\n", want
}

// m75LayeredLeaf mirrors the program's single runtime path: one or two
// layers advance per frame on every eighth seed, and the leaf adds the
// cell's defaulted-method value.
func m75LayeredLeaf(cellValue uint64) uint64 {
	seed := uint64(0)
	for i := 0; ; {
		if i == m75LayeredDepth-1 {
			return seed + cellValue
		}
		if i+2 <= m75LayeredDepth-1 && seed%8 == 0 {
			seed += 2
			i += 2
			continue
		}
		seed++
		i++
	}
}

// m75LayeredRejectProgram breaks one mid-stack layer with a call no trait
// provides.
func m75LayeredRejectProgram() string {
	declarations, _ := m75LayeredDeclarations()
	broken := append([]string(nil), declarations...)
	for at, declaration := range broken {
		if strings.HasPrefix(declaration, "fn layer_017(") {
			broken[at] = strings.Replace(declaration, "where P: Deliver(U64) {\n", "where P: Deliver(U64) {\n    if p.absent() { return 0 }\n", 1)
		}
	}
	return strings.Join(broken, "\n\n") + "\n"
}

// m75LayeredSplitFiles cuts the program into per-declaration round-robin
// chunks under names whose canonical order differs from the CLI order.
func m75LayeredSplitFiles(text string) map[string]string {
	chunks := make([]string, m75LayeredSplits)
	for i, declaration := range strings.Split(strings.TrimSuffix(text, "\n"), "\n\n") {
		chunks[i%m75LayeredSplits] += declaration + "\n\n"
	}
	names := []string{"z-tail.al", "a-head.al", "m-middle.al"}
	files := make(map[string]string, m75LayeredSplits)
	for at, name := range names {
		files[name] = chunks[at]
	}
	return files
}

func TestM75LayeredDagProduction(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)
	text, want := m75LayeredDagProgram()

	t.Run("accept-deterministic", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"layered.al": text}
		mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "layered.al")
		if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
			t.Fatalf("layered DAG MIR result: %+v", mirText)
		}
		repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "layered.al")
		if repeat != mirText {
			t.Fatalf("layered DAG MIR changed across processes")
		}
		cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "layered.al")
		if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
			t.Fatalf("layered DAG C result: %+v", cResult)
		}
		if cRepeat := runProductionCompiler(t, exe, files, "compile", "--emit=c", "layered.al"); cRepeat != cResult {
			t.Fatalf("layered DAG C changed across processes")
		}
		if len(want) != 3 {
			t.Fatalf("expected three leaf results, got %d", len(want))
		}
		compileAndRunProductionArtifact(t, "gcc", root, runtimeObject, cResult.stdout, 0)
	})

	t.Run("accept-permutations", func(t *testing.T) {
		t.Parallel()
		files := m75LayeredSplitFiles(text)
		first := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "z-tail.al", "a-head.al", "m-middle.al")
		if first.status != 0 || first.stderr != "" {
			t.Fatalf("layered DAG permutation MIR result: %+v", first)
		}
		second := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "m-middle.al", "z-tail.al", "a-head.al")
		if second != first {
			t.Fatalf("layered DAG MIR changed across CLI permutations")
		}
		cFirst := runProductionCompiler(t, exe, files, "compile", "--emit=c", "a-head.al", "m-middle.al", "z-tail.al")
		if cFirst.status != 0 || cFirst.stderr != "" {
			t.Fatalf("layered DAG permutation C result: %+v", cFirst)
		}
		if cSecond := runProductionCompiler(t, exe, files, "compile", "--emit=c", "z-tail.al", "m-middle.al", "a-head.al"); cSecond != cFirst {
			t.Fatalf("layered DAG C changed across CLI permutations")
		}
		compileAndRunProductionArtifact(t, "gcc", root, runtimeObject, cFirst.stdout, 0)
	})

	t.Run("reject-deterministic", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"broken.al": m75LayeredRejectProgram()}
		first := runProductionCompiler(t, exe, files, "check", "broken.al")
		if first.status == 0 || first.stderr == "" {
			t.Fatalf("layered DAG reject unexpectedly succeeded: %+v", first)
		}
		if repeat := runProductionCompiler(t, exe, files, "check", "broken.al"); repeat != first {
			t.Fatalf("layered DAG diagnostics changed across processes")
		}
		split := m75LayeredSplitFiles(m75LayeredRejectProgram())
		permuted := runProductionCompiler(t, exe, split, "check", "m-middle.al", "z-tail.al", "a-head.al")
		if permuted.status == 0 || permuted.stderr == "" {
			t.Fatalf("layered DAG split reject unexpectedly succeeded: %+v", permuted)
		}
		if repeat := runProductionCompiler(t, exe, split, "check", "a-head.al", "m-middle.al", "z-tail.al"); repeat != permuted {
			t.Fatalf("layered DAG split diagnostics changed across CLI permutations")
		}
	})
}
