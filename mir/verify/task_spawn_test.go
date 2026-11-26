package verify

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/4fuu/alder/mir"
)

// taskSpawnFixture parses the accepted task.spawn module so focused rejections
// can mutate one property without repeating the step declarations.
func taskSpawnFixture(t *testing.T) *mir.Module {
	t.Helper()
	text, err := os.ReadFile(filepath.Join("testdata", "verify", "accept", "task-spawn.mir"))
	if err != nil {
		t.Fatal(err)
	}
	m, err := mir.Parse(string(text))
	if err != nil {
		t.Fatalf("parse task.spawn fixture: %v", err)
	}
	return m
}

func taskSpawnInstr(t *testing.T, m *mir.Module) (*mir.Function, *mir.Instr) {
	t.Helper()
	id, ok := m.Function("__alder_step.run.spawner")
	if !ok {
		t.Fatal("spawner step missing")
	}
	f := m.Functions[id]
	for _, b := range f.Blocks {
		for i := range b.Instrs {
			if b.Instrs[i].Op == mir.OpTaskSpawn {
				return f, &b.Instrs[i]
			}
		}
	}
	t.Fatal("task.spawn instruction missing")
	return nil, nil
}

func TestTaskSpawnRequiresFormat7(t *testing.T) {
	m := taskSpawnFixture(t)
	m.FormatVersion = mir.BindingFormatVersion
	errs := Module(m)
	if !containsMsg(errs, "task.spawn requires MIR format version 7") {
		t.Fatalf("MIR 6 task.spawn not rejected:\n%s", Errors(errs).String())
	}
}

func TestTaskSpawnResultTypeRejection(t *testing.T) {
	m := taskSpawnFixture(t)
	f, in := taskSpawnInstr(t, m)
	f.Values[in.Result].Type = mir.TypeI64
	errs := Module(m)
	if !containsMsg(errs, "result type mismatch: stored i64, expected u64") {
		t.Fatalf("task.spawn result type mismatch not reported:\n%s", Errors(errs).String())
	}
}
