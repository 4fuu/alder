package compiler

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestSysrootPublicSurfaceUsesNoCSpellings keeps the provider-free std surface
// free of C ABI types. A sysroot signature, public field, public enum payload,
// type alias, or constant type has no reason to spell c.*: raw C types belong
// inside a wrapper body or behind the sysroot's audited C binding. Checking
// every non-raw function signature also covers inherent methods of public
// types, which do not carry an explicit `pub` marker.
func TestSysrootPublicSurfaceUsesNoCSpellings(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var files []string
	err = filepath.WalkDir(filepath.Join(root, "sysroot"), func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && strings.HasSuffix(path, ".al") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("sysroot has no Alder sources")
	}
	for _, path := range files {
		source, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			t.Fatal(err)
		}
		checkSysrootSurface(t, relative, source)
	}
}

type alderSurfaceToken struct {
	text string
	line int
}

func checkSysrootSurface(t *testing.T, path string, source []byte) {
	t.Helper()
	for _, violation := range sysrootSurfaceViolations(path, source) {
		t.Error(violation)
	}
}

func sysrootSurfaceViolations(path string, source []byte) []string {
	var violations []string
	tokens := scanAlderSurface(source)
	report := func(line int, what string) {
		violations = append(violations, fmt.Sprintf("%s:%d: %s spells a C type on the public surface", path, line, what))
	}

	for at := 0; at < len(tokens); at++ {
		if tokens[at].text != "fn" || at+2 >= len(tokens) || !surfaceIdentifier(tokens[at+1].text) || tokens[at+2].text != "(" {
			continue
		}
		// `raw fn` and `callback type` are the binding surface, not an Alder
		// wrapper signature; both intentionally name C ABI types.
		if at > 0 && (tokens[at-1].text == "raw" || tokens[at-1].text == "callback") {
			continue
		}
		close := surfaceMatch(tokens, at+2, "(", ")")
		if close < 0 {
			continue
		}
		end := close + 1
		for end < len(tokens) {
			if tokens[end].text == "{" || tokens[end].text == "=>" || tokens[end].text == ";" || tokens[end].line != tokens[close].line {
				break
			}
			end++
		}
		if surfaceCDot(tokens, at, end) {
			report(tokens[at].line, "function signature")
		}
	}

	for at := 0; at < len(tokens); at++ {
		if tokens[at].text != "pub" || at+1 >= len(tokens) {
			continue
		}
		switch tokens[at+1].text {
		case "type", "record":
			open := surfaceNext(tokens, at+2, "{")
			if open < 0 {
				// A public type alias has no field block. Check its type up to
				// the end of the declaration line.
				end := surfaceLineEnd(tokens, at+2)
				if surfaceCDot(tokens, at+2, end) {
					report(tokens[at].line, "public type alias")
				}
				continue
			}
			close := surfaceMatch(tokens, open, "{", "}")
			if close < 0 {
				continue
			}
			depth := 1
			for field := open + 1; field < close; field++ {
				switch tokens[field].text {
				case "{":
					depth++
				case "}":
					depth--
				case "pub":
					if depth != 1 {
						continue
					}
					end := surfaceFieldEnd(tokens, field+1, close)
					if surfaceCDot(tokens, field+1, end) {
						report(tokens[field].line, "public field")
					}
				}
			}
		case "enum":
			open := surfaceNext(tokens, at+2, "{")
			if open < 0 {
				continue
			}
			close := surfaceMatch(tokens, open, "{", "}")
			if close < 0 {
				continue
			}
			depth := 1
			for variant := open + 1; variant < close; variant++ {
				switch tokens[variant].text {
				case "{":
					depth++
				case "}":
					depth--
				}
				if depth != 1 || variant+1 >= close || tokens[variant+1].text != "(" {
					continue
				}
				payload_close := surfaceMatch(tokens, variant+1, "(", ")")
				if payload_close > variant && surfaceCDot(tokens, variant+1, payload_close) {
					report(tokens[variant].line, "public enum payload")
				}
			}
		case "const":
			end := surfaceLineEnd(tokens, at+2)
			if surfaceCDot(tokens, at+2, end) {
				report(tokens[at].line, "public constant type")
			}
		}
	}
	return violations
}

func TestSysrootSurfaceScannerRejectsCSpellings(t *testing.T) {
	const bad = `pub type Bad {
    pub pointer: c.Ptr(c.Char)
}

pub fn leak(value: c.Int) -> Unit {
    return
}

pub enum BadEnum {
    Value(c.Ptr(c.Char))
}
`
	if violations := sysrootSurfaceViolations("bad.al", []byte(bad)); len(violations) < 3 {
		t.Fatalf("surface scanner missed public C spellings: %v", violations)
	}
	const good = `import c "bad.h" as raw {
    raw fn call(value: c.Int) -> Unit
}

pub type Good {
    pub data: Bytes
}

pub fn safe(value: U64) -> U64 {
    unsafe c { raw.call(value.to_c_int()) }
    return value
}
`
	if violations := sysrootSurfaceViolations("good.al", []byte(good)); len(violations) != 0 {
		t.Fatalf("surface scanner rejected safe declarations: %v", violations)
	}
}

func scanAlderSurface(source []byte) []alderSurfaceToken {
	var tokens []alderSurfaceToken
	line := 1
	for at := 0; at < len(source); {
		c := source[at]
		if c == '\n' {
			line++
			at++
			continue
		}
		if c == ' ' || c == '\t' || c == '\r' {
			at++
			continue
		}
		if c == '/' && at+1 < len(source) && source[at+1] == '/' {
			for at < len(source) && source[at] != '\n' {
				at++
			}
			continue
		}
		if c == '/' && at+1 < len(source) && source[at+1] == '*' {
			at += 2
			for at+1 < len(source) && !(source[at] == '*' && source[at+1] == '/') {
				if source[at] == '\n' {
					line++
				}
				at++
			}
			if at+1 < len(source) {
				at += 2
			}
			continue
		}
		if c == '"' {
			at++
			for at < len(source) {
				if source[at] == '\\' {
					at += 2
					continue
				}
				if source[at] == '"' {
					at++
					break
				}
				if source[at] == '\n' {
					line++
				}
				at++
			}
			continue
		}
		if surfaceIdentifierStart(c) {
			start := at
			for at < len(source) && surfaceIdentifierPart(source[at]) {
				at++
			}
			tokens = append(tokens, alderSurfaceToken{text: string(source[start:at]), line: line})
			continue
		}
		if c >= '0' && c <= '9' {
			start := at
			for at < len(source) && (source[at] >= '0' && source[at] <= '9' || source[at] == '_' || source[at] == '.') {
				at++
			}
			tokens = append(tokens, alderSurfaceToken{text: string(source[start:at]), line: line})
			continue
		}
		if c == '-' && at+1 < len(source) && source[at+1] == '>' {
			tokens = append(tokens, alderSurfaceToken{text: "->", line: line})
			at += 2
			continue
		}
		tokens = append(tokens, alderSurfaceToken{text: string(c), line: line})
		at++
	}
	return tokens
}

func surfaceIdentifierStart(c byte) bool {
	return c == '_' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'
}

func surfaceIdentifierPart(c byte) bool {
	return surfaceIdentifierStart(c) || c >= '0' && c <= '9'
}

func surfaceIdentifier(text string) bool {
	return text != "" && surfaceIdentifierStart(text[0])
}

func surfaceMatch(tokens []alderSurfaceToken, open int, left, right string) int {
	if open < 0 || open >= len(tokens) || tokens[open].text != left {
		return -1
	}
	depth := 0
	for at := open; at < len(tokens); at++ {
		if tokens[at].text == left {
			depth++
		}
		if tokens[at].text == right {
			depth--
			if depth == 0 {
				return at
			}
		}
	}
	return -1
}

func surfaceNext(tokens []alderSurfaceToken, start int, text string) int {
	for at := start; at < len(tokens); at++ {
		if tokens[at].text == text {
			return at
		}
		if tokens[at].text == "=" || tokens[at].text == ";" {
			return -1
		}
	}
	return -1
}

func surfaceLineEnd(tokens []alderSurfaceToken, start int) int {
	if start >= len(tokens) {
		return len(tokens)
	}
	end := start
	for end < len(tokens) && tokens[end].line == tokens[start].line {
		end++
	}
	return end
}

func surfaceFieldEnd(tokens []alderSurfaceToken, start, limit int) int {
	if start >= limit {
		return limit
	}
	end := start
	for end < limit && tokens[end].line == tokens[start].line && tokens[end].text != "}" {
		end++
	}
	return end
}

func surfaceCDot(tokens []alderSurfaceToken, start, end int) bool {
	for at := start; at+1 < end; at++ {
		if tokens[at].text == "c" && tokens[at+1].text == "." {
			return true
		}
	}
	return false
}
