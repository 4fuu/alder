// Package compiler provides the pure, filesystem-independent Alder compiler service.
package compiler

import (
	"errors"
	"fmt"
	"path"
	"sort"
	"strings"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
)

// EmitKind selects the requested output. EmitNone performs checking only.
type EmitKind string

const (
	EmitNone EmitKind = "none"
	EmitMIR  EmitKind = "mir"
	EmitC    EmitKind = "c"
)

type Request struct {
	Sources []frontend.Source
	Emit    EmitKind
}

type Artifact struct {
	Kind EmitKind
	Text string
}

type Result struct {
	Diagnostics []frontend.Diagnostic
	Artifact    *Artifact
}

// ErrorKind classifies service failures that are not source diagnostics.
type ErrorKind string

const (
	ErrorInvalidRequest ErrorKind = "invalid_request"
	ErrorInternal       ErrorKind = "internal"
)

// ServiceError is returned for invalid requests and compiler invariant failures.
type ServiceError struct {
	Kind    ErrorKind
	Message string
	Cause   error
}

func (e *ServiceError) Error() string {
	if e.Cause != nil {
		return e.Message + ": " + e.Cause.Error()
	}
	return e.Message
}

func (e *ServiceError) Unwrap() error { return e.Cause }

// Compile compiles an explicitly identified source set as one global unit.
// The request is copied and ordered by canonical logical path; caller-owned
// source slices and elements are never mutated.
func Compile(req Request) (Result, error) {
	if len(req.Sources) == 0 {
		return Result{}, requestError("at least one source is required")
	}
	if req.Emit != EmitNone && req.Emit != EmitMIR && req.Emit != EmitC {
		return Result{}, requestError("invalid emit kind")
	}
	sources := append([]frontend.Source(nil), req.Sources...)
	sort.Slice(sources, func(i, j int) bool {
		if sources[i].Path != sources[j].Path {
			return sources[i].Path < sources[j].Path
		}
		return sources[i].ID < sources[j].ID
	})
	paths := make(map[string]bool, len(sources))
	ids := make(map[frontend.SourceID]bool, len(sources))
	for _, source := range sources {
		if !ValidLogicalPath(source.Path) {
			return Result{}, requestError("source path must be a non-empty canonical relative slash path")
		}
		if paths[source.Path] {
			return Result{}, requestError(fmt.Sprintf("duplicate source path %q", source.Path))
		}
		paths[source.Path] = true
		if source.ID == 0 {
			return Result{}, requestError(fmt.Sprintf("source %q must have a nonzero source ID", source.Path))
		}
		if ids[source.ID] {
			return Result{}, requestError(fmt.Sprintf("duplicate source ID %d", source.ID))
		}
		ids[source.ID] = true
	}
	m, diagnostics, err := frontend.CompileSources(sources)
	if err != nil {
		return Result{}, internalError("frontend failure", err)
	}
	if len(diagnostics) != 0 {
		return Result{Diagnostics: frontend.SortDiagnosticsBySource(diagnostics, sources)}, nil
	}
	// frontend.CompileSources already ran the complete verifier. EmitMIR
	// and EmitC both trust that result; GenerateProgram remains the
	// verified-only gate for untrusted MIR.
	result := Result{Diagnostics: []frontend.Diagnostic{}}
	switch req.Emit {
	case EmitNone:
		return result, nil
	case EmitMIR:
		result.Artifact = &Artifact{Kind: EmitMIR, Text: mir.Print(m)}
	case EmitC:
		text, err := cgen.GenerateProgramTrusted(m)
		if err != nil {
			var entryError *cgen.ProgramEntryError
			if errors.As(err, &entryError) {
				return Result{}, requestError(entryError.Error())
			}
			return Result{}, internalError("C backend failure", err)
		}
		result.Artifact = &Artifact{Kind: EmitC, Text: text}
	}
	return result, nil
}

// ValidLogicalPath reports whether name is a clean, non-empty, relative slash
// path. Logical paths are platform independent and cannot contain colons or
// backslashes, be absolute, or escape their logical root.
func ValidLogicalPath(name string) bool {
	return name != "" && !strings.ContainsAny(name, "\\:\x00") && !strings.HasPrefix(name, "/") && path.Clean(name) == name && name != "." && name != ".." && !strings.HasPrefix(name, "../")
}

func requestError(message string) error {
	return &ServiceError{Kind: ErrorInvalidRequest, Message: message}
}

func internalError(message string, cause error) error {
	return &ServiceError{Kind: ErrorInternal, Message: fmt.Sprintf("internal compiler error: %s", message), Cause: cause}
}
