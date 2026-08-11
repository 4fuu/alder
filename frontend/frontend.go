package frontend

import (
	"fmt"

	"github.com/4fuu/aster/mir"
	"github.com/4fuu/aster/mir/verify"
)

// Compile compiles a source module to a MIR module. Type inference and
// monomorphization complete before any backend MIR exists. The result is
// deterministic and must pass mir/verify unchanged; the cgen package enforces
// that gate on its own.
func Compile(src string) (*mir.Module, error) {
	decls, err := parseModule(src)
	if err != nil {
		return nil, err
	}
	cm, err := checkModule(decls)
	if err != nil {
		return nil, err
	}
	m, err := lowerModule(decls, cm)
	if err != nil {
		return nil, err
	}
	if errs := verify.Module(m); len(errs) != 0 {
		return nil, fmt.Errorf("internal frontend error: emitted invalid MIR: %s", verify.Errors(errs).String())
	}
	return m, nil
}
