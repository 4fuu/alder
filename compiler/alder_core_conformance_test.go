package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// coreConformanceSourceManifest is the exact fixed union closure for the
// checker, MIR printer, and MIR verifier V1-V10 harnesses. Production main.al is
// deliberately excluded, and no source is discovered from the filesystem.
var coreConformanceSourceManifest = []string{
	"checker.al",
	"cgen/program.al",
	"cgen/types.al",
	"cgen/writer.al",
	"host.al",
	"lexer.al",
	"lower.al",
	"mir_build.al",
	"mir_model.al",
	"mir_print.al",
	"model.al",
	"output.al",
	"parser.al",
	"verify_analysis.al",
	"verify_model.al",
	"verify_phase1.al",
	"verify_phase2.al",
	"verify_phase3.al",
	"verify_phase4.al",
	"verify_phase5.al",
	"verify_phase6.al",
	"verify_phase7.al",
	"verify_phase8.al",
	"verify_phase9.al",
	"verify_phase10.al",
}

const coreConformanceDispatch = `
fn host_path_is(source: U64, word: String) -> Bool {
    if unsafe c { alderhost_source_path_len(source) } != len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if unsafe c { alderhost_source_path_byte(source, at) } != word[at] { return false }
        at = at + 1
    }
    return true
}

fn main(d: Domain) -> I32 {
    if unsafe c { alderhost_source_count() } == 0 { return 2 }
    if host_path_is(0, "!alder-core-checker") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad-k") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad-m") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad-w") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad-x") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-lower-bad-g") { return checker_mode(d) }
	if host_path_is(0, "!alder-core-cgen") { return cgen_mode(d) }
    if host_path_is(0, "!alder-core-printer") { return printer_mode(d) }
    if host_path_is(0, "!alder-core-verifier") { return verifier_mode(d) }
    return 2
}
`

const checkerSentinelLoader = `
fn checker_load_sources(d: Domain, state: State) -> Result(State, __s0_Error) {
    var paths = state.paths
    var texts = state.texts
    var sources = state.sources
    let count = unsafe c { alderhost_source_count() }
    var source: U64 = 1
    while source < count {
        let path_len = unsafe c { alderhost_source_path_len(source) }
        let text_len = unsafe c { alderhost_source_text_len(source) }
        let path_start = __s0_buffer_len(U8, paths)
        paths = try copy_host_path(d, paths, source, path_len)
        let text_start = __s0_buffer_len(U8, texts)
        texts = try copy_host_text(d, texts, source, text_len)
        sources = try __s0_buffer_append(SourceRec, d, sources, SourceRec(path_start: path_start, path_end: path_start + path_len, text_start: text_start, text_end: text_start + text_len))
        source = source + 1
    }
    return Ok(State(paths: paths, texts: texts, values: state.values, sources: sources, tokens: state.tokens, diagnostics: state.diagnostics))
}
fn loaded(d: Domain,state: State) -> I32 { return match checker_load_sources(d,state) {
    Err(error) => 3
    Ok(value) => pi_nodes(d,value)
} }
`

func coreConformanceWrapper() string {
	checker := strings.ReplaceAll(checkerWrapper, " { Err", " {\n Err")
	checker = strings.ReplaceAll(checker, " 3 Ok", " 3\n Ok")
	checker = strings.ReplaceAll(checker, " Err(", "\n Err(")
	checker = strings.ReplaceAll(checker, " Ok(", "\n Ok(")
	checker = strings.Replace(checker, "fn loaded(d: Domain,state: State) -> I32 { return match load_sources(d,state) {\n\n Err(e)=>3\n Ok(s)=>pi_nodes(d,s) } }", checkerSentinelLoader, 1)
	checker = strings.Replace(checker, "fn checker_good(state: State, parse: ParseStore, store: CheckStore) -> I32 {\n if !emit_check_manifest(state, parse, store) { return 4 }\n return 0\n}", "fn checker_good(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> I32 {\n if host_path_is(0, \"!alder-core-lower\") { return lower_mode(d, state, parse, store) }\n if !emit_check_manifest(state, parse, store) { return 4 }\n return 0\n}", 1)
	checker = strings.Replace(checker, "if host_path_is(0, \"!alder-core-lower\") { return lower_mode(d, state, parse, store) }", "if host_path_is(0, \"!alder-core-lower\") || host_path_is(0, \"!alder-core-lower-bad\") || host_path_is(0, \"!alder-core-lower-bad-k\") || host_path_is(0, \"!alder-core-lower-bad-m\") || host_path_is(0, \"!alder-core-lower-bad-w\") || host_path_is(0, \"!alder-core-lower-bad-x\") || host_path_is(0, \"!alder-core-lower-bad-g\") { return lower_mode(d, state, parse, store) }", 1)
	checker = strings.Replace(checker, "fn checker_done(state: State, parse: ParseStore, result: CheckResult) -> I32", "fn checker_done(d: Domain, state: State, parse: ParseStore, result: CheckResult) -> I32", 1)
	checker = strings.Replace(checker, "CheckGood(store) => checker_good(state, parse, store)", "CheckGood(store) => checker_good(d, state, parse, store)", 1)
	checker = strings.Replace(checker, "Ok(result) => checker_done(output.state, output.store, result)", "Ok(result) => checker_done(d, output.state, output.store, result)", 1)
	checker = strings.Replace(checker, "fn main(d: Domain)", "fn checker_mode(d: Domain)", 1)

	printer := strings.TrimPrefix(mirPrinterWrapper, "\nimport c alderhost_stdout_byte: fn(U8) -> Bool\nimport c alderhost_stdout_f64_bits: fn(U64) -> Bool\n")
	printer = strings.Replace(printer, "fn main(d: Domain)", "fn printer_mode(d: Domain)", 1)

	verifier := strings.TrimPrefix(mirVerifyWrapper, "\nimport c alderhost_stdout_byte: fn(U8) -> Bool\n")
	verifier = strings.Replace(verifier, "fn main(d: Domain)", "fn verifier_mode(d: Domain)", 1)
	return checker + printer + verifier + cgenSkeletonWrapper + `
fn lower_print(mir: MirStore) -> I32 {
    if mir_print(mir) { return 0 }
    return 5
}
fn lower_expect_bad(result: LowerResult) -> I32 { return match result {
    LowerBad => 0
    LowerGood(mir) => 5
} }
fn lower_bad_done(result: Result(LowerResult, __s0_Error)) -> I32 { return match result {
    Err(error) => 3
    Ok(value) => lower_expect_bad(value)
} }
fn lower_bad_blocks(d: Domain, state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, blocks: __s0_Buffer(CheckedBlockRec)) -> I32 {
    return match __s0_buffer_append(CheckedBlockRec, d, blocks, CheckedBlockRec(owner: 999, syntax: 1, environment: 0, statements: 0, guaranteed_return: 0)) {
        Err(error) => 3
        Ok(bad_blocks) => lower_bad_done(lower_checked(d, state, spans, CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: CheckedControlStore(blocks: bad_blocks, statement_links: store.control.statement_links, statements: store.control.statements, places: store.control.places, matches: store.control.matches, match_arms: store.control.match_arms, tries: store.control.tries, cleanups: store.control.cleanups), diagnostics: store.diagnostics)))
    }
}
fn lower_bad_control(d: Domain, state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore) -> Result(I32, __s0_Error) {
    var control = store.control
    if host_path_is(0, "!alder-core-lower-bad-k") { control = CheckedControlStore(blocks: control.blocks, statement_links: try __s0_buffer_append(CheckedStatementLinkRec, d, control.statement_links, CheckedStatementLinkRec(statement: 999, next: 0)), statements: control.statements, places: control.places, matches: control.matches, match_arms: control.match_arms, tries: control.tries, cleanups: control.cleanups) }
    if host_path_is(0, "!alder-core-lower-bad-m") { control = CheckedControlStore(blocks: control.blocks, statement_links: control.statement_links, statements: control.statements, places: control.places, matches: try __s0_buffer_append(CheckedMatchRec, d, control.matches, CheckedMatchRec(owner: 999, syntax: 1, scrutinee: 1, scrutinee_type: 1, checked_type: 1, first_arm: 1, arm_count: 1)), match_arms: control.match_arms, tries: control.tries, cleanups: control.cleanups) }
    if host_path_is(0, "!alder-core-lower-bad-w") { control = CheckedControlStore(blocks: control.blocks, statement_links: control.statement_links, statements: control.statements, places: control.places, matches: control.matches, match_arms: try __s0_buffer_append(CheckedMatchArmRec, d, control.match_arms, CheckedMatchArmRec(owner: 999, syntax: 1, checked_match: 999, variant_use: 0, variant_kind: 7, binding: 0, environment: 0, body: 1)), tries: control.tries, cleanups: control.cleanups) }
    if host_path_is(0, "!alder-core-lower-bad-x") { control = CheckedControlStore(blocks: control.blocks, statement_links: control.statement_links, statements: control.statements, places: control.places, matches: control.matches, match_arms: control.match_arms, tries: try __s0_buffer_append(CheckedTryRec, d, control.tries, CheckedTryRec(owner: 999, syntax: 1, expression: 999, result_type: 1, ok_type: 1, error_type: 1)), cleanups: control.cleanups) }
    if host_path_is(0, "!alder-core-lower-bad-g") { control = CheckedControlStore(blocks: control.blocks, statement_links: control.statement_links, statements: control.statements, places: control.places, matches: control.matches, match_arms: control.match_arms, tries: control.tries, cleanups: try __s0_buffer_append(CheckedCleanupRec, d, control.cleanups, CheckedCleanupRec(owner: 999, syntax: 1, environment: 999, binding: 999, initializer: 999, callback: 999, normal_exit: 1, return_exit: 1, try_exit: 1))) }
    return Ok(lower_bad_done(lower_checked(d, state, spans, CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: control, diagnostics: store.diagnostics))))
}
fn lower_mode_spans(d: Domain, state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore) -> I32 {
    if host_path_is(0, "!alder-core-lower-bad") {
        return match __s0_buffer_new(CheckedBlockRec, d) {
            Err(error) => 3
            Ok(blocks) => lower_bad_blocks(d, state, spans, store, blocks)
        }
    }
    if host_path_is(0, "!alder-core-lower-bad-k") || host_path_is(0, "!alder-core-lower-bad-m") || host_path_is(0, "!alder-core-lower-bad-w") || host_path_is(0, "!alder-core-lower-bad-x") || host_path_is(0, "!alder-core-lower-bad-g") { return match lower_bad_control(d, state, spans, store) {
        Err(error) => 3
        Ok(status) => status
    } }
    return match lower_checked(d, state, spans, store) {
        Err(error) => 3
        Ok(result) => match result {
            LowerBad => 5
            LowerGood(mir) => lower_print(mir)
        }
    }
}
fn lower_mode(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> I32 { return match checked_spans(d, parse) {
    Err(error) => 3
    Ok(spans) => lower_mode_spans(d, state, spans, store)
} }
` + coreConformanceDispatch
}

func TestAlderCoreConformance(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}

	sources := make([]frontend.Source, 0, len(coreConformanceSourceManifest)+1)
	for i, name := range coreConformanceSourceManifest {
		text, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			t.Fatal(readErr)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	wrapper := coreConformanceWrapper()
	if strings.Contains(wrapper, "match load_sources(d,state)") {
		t.Fatal("checker sentinel loader was not installed")
	}
	sources = append(sources, frontend.Source{ID: frontend.SourceID(len(sources) + 1), Path: "compiler/test/core_conformance_main.al", Text: wrapper})

	// TestMultiSourcePermutationsProduceIdenticalMIRAndC owns source-order
	// determinism at the shared Compile-to-CompileSources canonicalization
	// boundary. Checker and production argv permutations plus repeated printer
	// and verifier processes retain executable-level determinism coverage here.
	compiled, err := Compile(Request{Sources: sources, Emit: EmitMIR})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile core closure: result=%+v error=%v", compiled, err)
	}

	module, err := mir.Parse(compiled.Artifact.Text)
	if err != nil {
		t.Fatalf("parse core conformance MIR: %v", err)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify core conformance MIR: %s", verify.Errors(diagnostics).String())
	}
	for _, name := range []string{"collect_cycle_edges", "reject_value_cycles", "interpreted_type_equal", "interpreted_may_reach_ancestry", "direct_type_concrete", "interpreted_contains_reference", "interpreted_map_key_ok", "validate_concrete_type", "revalidate_aggregate_roots"} {
		id, ok := module.Function(name)
		if !ok {
			t.Fatalf("core conformance MIR has no %s function", name)
		}
		for _, block := range module.Functions[id].Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op == mir.OpCall && instruction.Callee == id {
					t.Fatalf("%s recursively calls itself", name)
				}
			}
		}
	}

	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatalf("generate core conformance C: %v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "core-conformance.c")
	exe := filepath.Join(dir, "core-conformance.exe")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, cfile, filepath.Join(root, "bootstrap", "alder_host.c"), exe)

	t.Run("checker", func(t *testing.T) { runCheckerConformance(t, exe) })
	t.Run("lower", func(t *testing.T) { runLowerConformance(t, exe) })
	t.Run("cgen-skeleton", func(t *testing.T) { runCgenSkeletonConformance(t, cc, root, exe) })
	t.Run("printer", func(t *testing.T) { runMIRPrinterConformance(t, exe) })
	t.Run("verifier-v1-v10", func(t *testing.T) { runMIRVerifierConformance(t, exe) })
}
