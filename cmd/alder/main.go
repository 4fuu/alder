package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/4fuu/alder/compiler"
	"github.com/4fuu/alder/frontend"
)

const jsonVersion = 1

const (
	exitSuccess     = 0
	exitDiagnostics = 1
	exitUsage       = 2
	exitIO          = 3
	exitInternal    = 4
)

type position struct {
	Line   int `json:"line"`
	Column int `json:"column"`
}
type jsonRange struct {
	Path      string   `json:"path"`
	StartByte int      `json:"startByte"`
	EndByte   int      `json:"endByte"`
	Start     position `json:"start"`
	End       position `json:"end"`
}
type jsonRelated struct {
	Message string    `json:"message"`
	Range   jsonRange `json:"range"`
}
type jsonDiagnostic struct {
	Code     string        `json:"code"`
	Severity string        `json:"severity"`
	Message  string        `json:"message"`
	Range    jsonRange     `json:"range"`
	Related  []jsonRelated `json:"related"`
	Notes    []string      `json:"notes"`
}
type jsonArtifact struct {
	Kind    string `json:"kind"`
	Content string `json:"content,omitempty"`
	Path    string `json:"path,omitempty"`
}
type jsonFailure struct {
	Kind    string `json:"kind"`
	Message string `json:"message"`
}
type envelope struct {
	Version     int              `json:"version"`
	Command     string           `json:"command"`
	Success     bool             `json:"success"`
	Diagnostics []jsonDiagnostic `json:"diagnostics"`
	Artifact    *jsonArtifact    `json:"artifact,omitempty"`
	Failure     *jsonFailure     `json:"failure,omitempty"`
}

func main() {
	cwd, err := os.Getwd()
	if err != nil {
		os.Exit(fail(commandName(os.Args[1:]), wantsJSON(os.Args[1:]), os.Stdout, os.Stderr, exitIO, "io", "cannot determine working directory"))
	}
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, cwd))
}

func run(args []string, stdout, stderr io.Writer, cwd string) int {
	command := commandName(args)
	if command != "check" && command != "compile" {
		return fail(command, wantsJSON(args), stdout, stderr, exitUsage, "usage", "usage: alder check|compile [options] <file.al>...")
	}
	fs := flag.NewFlagSet(command, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	format := fs.String("format", "human", "")
	var emit, output *string
	if command == "compile" {
		emit = fs.String("emit", "c", "")
		output = fs.String("o", "", "")
	}
	if err := fs.Parse(args[1:]); err != nil {
		return fail(command, wantsJSON(args), stdout, stderr, exitUsage, "usage", "invalid command options")
	}
	jsonMode := *format == "json"
	if *format != "human" && !jsonMode {
		return fail(command, jsonMode, stdout, stderr, exitUsage, "usage", "format must be human or json")
	}
	if fs.NArg() == 0 {
		return fail(command, jsonMode, stdout, stderr, exitUsage, "usage", "at least one input file is required")
	}
	kind := compiler.EmitNone
	if command == "compile" {
		if *emit == "mir" {
			kind = compiler.EmitMIR
		} else if *emit == "c" {
			kind = compiler.EmitC
		} else {
			return fail(command, jsonMode, stdout, stderr, exitUsage, "request", "emit must be mir or c")
		}
	}
	logicalInputs := append([]string(nil), fs.Args()...)
	for _, logical := range logicalInputs {
		if filepath.Ext(logical) != ".al" {
			return fail(command, jsonMode, stdout, stderr, exitUsage, "request", "inputs must have the case-sensitive .al extension")
		}
		if !compiler.ValidLogicalPath(logical) {
			return fail(command, jsonMode, stdout, stderr, exitUsage, "request", "inputs must be canonical workspace-relative slash paths")
		}
	}
	sort.Strings(logicalInputs)
	for i := 1; i < len(logicalInputs); i++ {
		if logicalInputs[i] == logicalInputs[i-1] {
			return fail(command, jsonMode, stdout, stderr, exitUsage, "request", "duplicate input path")
		}
	}
	sources := make([]frontend.Source, 0, len(logicalInputs))
	sourceByID := make(map[frontend.SourceID]frontend.Source, len(logicalInputs))
	for i, logical := range logicalInputs {
		input, _, _ := workspacePath(cwd, logical)
		text, err := os.ReadFile(input)
		if err != nil {
			return fail(command, jsonMode, stdout, stderr, exitIO, "io", "cannot read input file")
		}
		source := frontend.Source{ID: frontend.SourceID(i + 1), Path: logical, Text: string(text)}
		sources = append(sources, source)
		sourceByID[source.ID] = source
	}
	result, err := compiler.Compile(compiler.Request{Sources: sources, Emit: kind})
	if err != nil {
		var service *compiler.ServiceError
		code := exitInternal
		class := "internal"
		message := "internal compiler failure"
		if errors.As(err, &service) && service.Kind == compiler.ErrorInvalidRequest {
			code, class, message = exitUsage, "request", service.Message
		}
		return fail(command, jsonMode, stdout, stderr, code, class, message)
	}
	diagnostics, err := adaptDiagnostics(sourceByID, result.Diagnostics)
	if err != nil {
		return fail(command, jsonMode, stdout, stderr, exitInternal, "internal", "internal compiler failure")
	}
	if len(diagnostics) != 0 {
		if jsonMode {
			if writeJSON(stdout, envelope{Version: jsonVersion, Command: command, Diagnostics: diagnostics}) != nil {
				return exitIO
			}
		} else {
			if writeHuman(stderr, diagnostics) != nil {
				return exitIO
			}
		}
		return exitDiagnostics
	}
	var artifact *jsonArtifact
	if result.Artifact != nil {
		artifact = &jsonArtifact{Kind: string(result.Artifact.Kind)}
		if output != nil && *output != "" {
			outPath, outLogical, valid := workspacePath(cwd, *output)
			if !valid {
				return fail(command, jsonMode, stdout, stderr, exitUsage, "request", "output must be a canonical workspace-relative slash path")
			}
			if err := atomicWrite(outPath, []byte(result.Artifact.Text)); err != nil {
				return fail(command, jsonMode, stdout, stderr, exitIO, "io", "cannot write output file")
			}
			artifact.Path = outLogical
		} else if jsonMode {
			artifact.Content = result.Artifact.Text
		} else {
			if _, err := io.WriteString(stdout, result.Artifact.Text); err != nil {
				return exitIO
			}
		}
	}
	if jsonMode {
		if writeJSON(stdout, envelope{Version: jsonVersion, Command: command, Success: true, Diagnostics: []jsonDiagnostic{}, Artifact: artifact}) != nil {
			return exitIO
		}
	}
	return exitSuccess
}

func workspacePath(cwd, name string) (string, string, bool) {
	if !compiler.ValidLogicalPath(name) {
		return "", "", false
	}
	return filepath.Join(cwd, filepath.FromSlash(name)), name, true
}

func adaptDiagnostics(sources map[frontend.SourceID]frontend.Source, in []frontend.Diagnostic) ([]jsonDiagnostic, error) {
	out := make([]jsonDiagnostic, 0, len(in))
	for _, d := range in {
		primary, err := adaptRange(sources, d.Primary)
		if err != nil {
			return nil, err
		}
		jd := jsonDiagnostic{Code: string(d.Code), Severity: string(d.Severity), Message: d.Message, Range: primary, Related: []jsonRelated{}, Notes: append([]string(nil), d.Notes...)}
		if jd.Notes == nil {
			jd.Notes = []string{}
		}
		for _, r := range d.Related {
			rng, err := adaptRange(sources, r.Span)
			if err != nil {
				return nil, err
			}
			jd.Related = append(jd.Related, jsonRelated{Message: r.Message, Range: rng})
		}
		out = append(out, jd)
	}
	return out, nil
}

func adaptRange(sources map[frontend.SourceID]frontend.Source, span frontend.Span) (jsonRange, error) {
	source, ok := sources[span.Source]
	if !ok {
		return jsonRange{}, fmt.Errorf("unknown source ID %d", span.Source)
	}
	if span.Start < 0 || span.End < span.Start || span.End > len(source.Text) {
		return jsonRange{}, fmt.Errorf("invalid source range [%d,%d) for source ID %d", span.Start, span.End, span.Source)
	}
	sl, sc := source.LineColumn(span.Start)
	el, ec := source.LineColumn(span.End)
	return jsonRange{Path: source.Path, StartByte: span.Start, EndByte: span.End, Start: position{sl, sc}, End: position{el, ec}}, nil
}

func writeHuman(w io.Writer, ds []jsonDiagnostic) error {
	for _, d := range ds {
		if _, err := fmt.Fprintf(w, "%s:%d:%d: %s[%s]: %s\n", d.Range.Path, d.Range.Start.Line, d.Range.Start.Column, d.Severity, d.Code, d.Message); err != nil {
			return err
		}
		for _, r := range d.Related {
			if _, err := fmt.Fprintf(w, "%s:%d:%d: related: %s\n", r.Range.Path, r.Range.Start.Line, r.Range.Start.Column, r.Message); err != nil {
				return err
			}
		}
		for _, n := range d.Notes {
			if _, err := fmt.Fprintf(w, "note: %s\n", n); err != nil {
				return err
			}
		}
	}
	return nil
}
func wantsJSON(args []string) bool {
	format := "human"
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			break
		}
		if a == "--format" || a == "-format" {
			if i+1 < len(args) {
				i++
				format = args[i]
			}
		} else if strings.HasPrefix(a, "--format=") || strings.HasPrefix(a, "-format=") {
			format = strings.SplitN(a, "=", 2)[1]
		}
	}
	return format == "json"
}

func commandName(args []string) string {
	if len(args) > 0 {
		return args[0]
	}
	return ""
}
func fail(command string, jsonMode bool, stdout, stderr io.Writer, code int, kind, message string) int {
	if jsonMode {
		if writeJSON(stdout, envelope{Version: jsonVersion, Command: command, Diagnostics: []jsonDiagnostic{}, Failure: &jsonFailure{Kind: kind, Message: message}}) != nil {
			return exitIO
		}
	} else {
		if _, err := fmt.Fprintln(stderr, "alder: "+message); err != nil {
			return exitIO
		}
	}
	return code
}
func writeJSON(w io.Writer, value envelope) error {
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	return enc.Encode(value)
}
func atomicWrite(name string, data []byte) error {
	dir := filepath.Dir(name)
	tmp, err := os.CreateTemp(dir, ".alder-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err = tmp.Write(data); err == nil {
		err = tmp.Sync()
	}
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmpName, name)
}
