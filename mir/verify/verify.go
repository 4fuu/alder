// Package verify implements the Aster MIR verifier: deterministic,
// source-independent diagnostics over the ten documented phases.
//
// Diagnostics are stable: they identify the owning function, block, and
// operation, and they are produced in declaration order within each phase.
package verify

import (
	"strconv"
	"strings"

	"github.com/4fuu/aster/mir"
)

// Error is one deterministic verifier diagnostic. Loc identifies the owning
// function, block, and operation; Msg is the reason.
type Error struct {
	Loc string
	Msg string
}

// String renders the diagnostic as "loc: msg" (or just msg for module-level
// issues).
func (e Error) String() string {
	if e.Loc == "" {
		return e.Msg
	}
	return e.Loc + ": " + e.Msg
}

// Errors is a deterministic diagnostic list.
type Errors []Error

// String renders every diagnostic, one per line.
func (es Errors) String() string {
	var b strings.Builder
	for i, e := range es {
		if i > 0 {
			b.WriteString("\n")
		}
		b.WriteString(e.String())
	}
	return b.String()
}

// Module verifies a complete module and returns deterministic diagnostics in
// phase order. An empty result means the module is valid.
func Module(m *mir.Module) []Error {
	if m == nil {
		return []Error{{Msg: "nil module"}}
	}
	var errs []Error
	errs = append(errs, phase1Integrity(m)...)
	errs = append(errs, phase2Types(m)...)
	errs = append(errs, phase3CFG(m)...)
	errs = append(errs, phase4Dominance(m)...)
	errs = append(errs, phase5Typing(m)...)
	errs = append(errs, phase6Domains(m)...)
	// Phases 7 through 10 (cleanup, tables, pointer boundaries, backend
	// preconditions) are added as they land.
	return errs
}

// Location helpers used by every phase.

func locFunc(f *mir.Function) string {
	return "fn @" + f.Name
}

func locBlock(f *mir.Function, b *mir.Block) string {
	return locFunc(f) + ": block " + b.Name
}

func locInstr(f *mir.Function, b *mir.Block, i int, in *mir.Instr) string {
	return locBlock(f, b) + ": op " + in.Op.String() + " #" + strconv.Itoa(i)
}

func locTerm(f *mir.Function, b *mir.Block) string {
	return locBlock(f, b) + ": terminator " + b.Term.Kind.String()
}
