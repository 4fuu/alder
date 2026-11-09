package compiler

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// The stage-0 bootstrap build splits the generated compiler into four fixed
// translation units and compiles them in parallel, because gcc's cost on one
// ~20 MB unit dominates a cold build. The test harness's two heavy builds
// compile the same generated shape — the shared production compiler and the
// core conformance executable — so they invoke bootstrap/split-c.awk, the
// same splitter regenerate.sh uses, instead of keeping a second
// implementation. The split is a build transform only: every part is
// compiled under the full strict warning set, the linked executables still
// run every original assertion, and the artifact cache digests the part
// objects exactly like the single-unit object they replace.

// splitCPlan is the splitter's cut plan for one generated C file.
type splitCPlan struct {
	hdrEnd, cut1, cut2, cut3, entry int
}

// splitCPath locates the committed shared splitter.
func splitCPath(root string) string {
	return filepath.Join(root, "bootstrap", "split-c.awk")
}

// planSplitC runs the shared splitter's plan mode over cfile and validates
// the plan the same way regenerate.sh does before handing it to write mode.
func planSplitC(root, cfile string) (splitCPlan, error) {
	var plan splitCPlan
	awk, err := exec.LookPath("awk")
	if err != nil {
		return plan, fmt.Errorf("find awk: %w", err)
	}
	out, err := exec.Command(awk, "-v", "mode=plan", "-f", splitCPath(root), cfile).CombinedOutput()
	if err != nil {
		return plan, fmt.Errorf("splitter plan failed: %w\n%s", err, out)
	}
	fields := strings.Fields(strings.TrimSpace(string(out)))
	if len(fields) != 5 {
		return plan, fmt.Errorf("splitter plan is not one line of five numbers: %q", string(out))
	}
	values := []*int{&plan.hdrEnd, &plan.cut1, &plan.cut2, &plan.cut3, &plan.entry}
	for i, value := range values {
		n, convErr := strconv.Atoi(fields[i])
		if convErr != nil || n <= 0 {
			return plan, fmt.Errorf("splitter plan field %d is not a positive number: %q", i, string(out))
		}
		*value = n
	}
	if plan.hdrEnd >= plan.cut1 || plan.cut1 >= plan.cut2 || plan.cut2 >= plan.cut3 || plan.cut3 >= plan.entry {
		return plan, fmt.Errorf("splitter plan is not strictly ordered: %+v", plan)
	}
	return plan, nil
}

// writeSplitC runs the shared splitter's write mode, which leaves
// alder_split.h, alder_split_inline.h, and part0.c..part3.c in partsDir.
func writeSplitC(root, cfile, partsDir string, plan splitCPlan) error {
	awk, err := exec.LookPath("awk")
	if err != nil {
		return fmt.Errorf("find awk: %w", err)
	}
	write := exec.Command(awk,
		"-v", "mode=write",
		"-v", "split_dir="+partsDir,
		"-v", fmt.Sprintf("hdr_end=%d", plan.hdrEnd),
		"-v", fmt.Sprintf("cut1=%d", plan.cut1),
		"-v", fmt.Sprintf("cut2=%d", plan.cut2),
		"-v", fmt.Sprintf("cut3=%d", plan.cut3),
		"-v", fmt.Sprintf("entry=%d", plan.entry),
		"-f", splitCPath(root), cfile)
	if out, err := write.CombinedOutput(); err != nil {
		return fmt.Errorf("splitter write failed: %w\n%s", err, out)
	}
	return nil
}

// splitCompilerC splits cfile into four translation units with the shared
// bootstrap/split-c.awk splitter and compiles the parts in parallel under
// the strict warning set plus extra, writing part0.o..part3.o into
// objectDir. The split sources live in partsDir; the caller creates it and
// removes it once the objects are no longer needed. The returned object
// paths are in part order, ready to link.
func splitCompilerC(t *testing.T, cc, root, cfile, partsDir, objectDir string, extra ...string) []string {
	t.Helper()
	objects, err := splitCompilerCErr(cc, root, cfile, partsDir, objectDir, extra...)
	if err != nil {
		t.Fatal(err)
	}
	return objects
}

// splitCompilerCErr is splitCompilerC without a testing.T, for build
// closures that report errors to the artifact cache instead of failing the
// test directly.
func splitCompilerCErr(cc, root, cfile, partsDir, objectDir string, extra ...string) ([]string, error) {
	if err := os.MkdirAll(partsDir, 0o755); err != nil {
		return nil, err
	}
	plan, err := planSplitC(root, cfile)
	if err != nil {
		return nil, err
	}
	if err := writeSplitC(root, cfile, partsDir, plan); err != nil {
		return nil, err
	}
	objects := make([]string, 4)
	failures := make([]error, 4)
	var group sync.WaitGroup
	for i := range objects {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			source := filepath.Join(partsDir, fmt.Sprintf("part%d.c", i))
			object := filepath.Join(objectDir, fmt.Sprintf("part%d.o", i))
			args := append([]string{}, strictC11Flags()...)
			args = append(args, extra...)
			args = append(args, "-I", partsDir,
				"-I", filepath.Join(root, "runtime", "c"),
				"-I", filepath.Join(root, "bootstrap"),
				"-c", source, "-o", object)
			if out, cmdErr := exec.Command(cc, args...).CombinedOutput(); cmdErr != nil {
				failures[i] = fmt.Errorf("strict C11 compile of part %d: %w\n%s", i, cmdErr, out)
				return
			}
			objects[i] = object
		}(i)
	}
	group.Wait()
	for _, failure := range failures {
		if failure != nil {
			return nil, failure
		}
	}
	return objects, nil
}
