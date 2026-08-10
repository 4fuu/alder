package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase3CFG checks control-flow structure: valid targets, matching block
// argument counts, switch case validity and exhaustiveness, entry-block
// parameters, and unreachable placement.
func phase3CFG(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		reach := reachable(f)
		if len(f.Blocks[0].Params) > 0 {
			errs = append(errs, Error{Loc: locBlock(f, f.Blocks[0]), Msg: "entry block may not have parameters"})
		}
		for bi, b := range f.Blocks {
			if b == nil {
				continue
			}
			loc := locBlock(f, b)
			checkTarget := func(what string, target mir.BlockId, args []mir.ValueId) {
				if target == mir.NoBlock {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s has no target", what)})
					return
				}
				if int(target) >= len(f.Blocks) {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s target out of range", what)})
					return
				}
				want := len(f.Blocks[target].Params)
				if len(args) != want {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s: expected %d edge arguments, got %d", what, want, len(args))})
				}
			}
			for i := range b.Instrs {
				in := &b.Instrs[i]
				if in.FailTarget != mir.NoBlock {
					checkTarget("failure edge", in.FailTarget, in.FailArgs)
				}
			}
			switch b.Term.Kind {
			case mir.TermJump:
				checkTarget("jump", b.Term.Target, b.Term.Args)
			case mir.TermBranch:
				checkTarget("branch true edge", b.Term.Then, b.Term.ThenArgs)
				checkTarget("branch false edge", b.Term.Else, b.Term.ElseArgs)
			case mir.TermSwitch:
				if len(b.Term.Cases) == 0 {
					errs = append(errs, Error{Loc: loc, Msg: "switch has no cases"})
				}
				seen := make(map[string]bool)
				hasDefault := false
				for _, c := range b.Term.Cases {
					if c.Variant == "" {
						if hasDefault {
							errs = append(errs, Error{Loc: loc, Msg: "switch has more than one default case"})
						}
						hasDefault = true
					} else if seen[c.Variant] {
						errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("duplicate switch case %q", c.Variant)})
					}
					seen[c.Variant] = true
					checkTarget("switch case", c.Target, c.Args)
				}
				if !hasDefault {
					if vt, ok := f.ValueType(b.Term.Value); ok {
						if vs, ok := m.VariantsOf(vt); ok {
							for _, v := range vs {
								if !seen[v.Name] {
									errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("switch does not cover variant %q and has no default", v.Name)})
								}
							}
						}
					}
				}
			case mir.TermFail:
				if b.Term.Result == mir.NoValue {
					errs = append(errs, Error{Loc: loc, Msg: "fail requires a value"})
				}
			case mir.TermUnreachable:
				if reach[bi] {
					errs = append(errs, Error{Loc: loc, Msg: "unreachable terminator in a reachable block"})
				}
			}
		}
	}
	return errs
}
