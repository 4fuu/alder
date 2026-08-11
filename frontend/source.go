package frontend

import "unicode/utf8"

// SourceID is the stable numeric identity of a source within a compilation.
type SourceID uint32

// Source is an immutable-by-convention source file. Text is retained verbatim.
type Source struct {
	ID   SourceID
	Path string
	Text string
}

// Span is a half-open UTF-8 byte range in a Source.
type Span struct {
	Source SourceID
	Start  int
	End    int
}

// NewSpan returns a range clamped to the source's byte bounds.
func NewSpan(source Source, start, end int) Span {
	if start < 0 {
		start = 0
	}
	if start > len(source.Text) {
		start = len(source.Text)
	}
	if end < start {
		end = start
	}
	if end > len(source.Text) {
		end = len(source.Text)
	}
	return Span{Source: source.ID, Start: start, End: end}
}

// LineColumn converts a byte offset to a 1-based line and Unicode-code-point
// column. The offset is clamped and offsets within a UTF-8 encoding count as
// the containing code point. CRLF is one line break and a lone CR is ordinary
// column content, matching the frontend's existing newline rules.
func (s Source) LineColumn(offset int) (line, column int) {
	if offset < 0 {
		offset = 0
	}
	if offset > len(s.Text) {
		offset = len(s.Text)
	}
	line, column = 1, 1
	for i := 0; i < offset; {
		if s.Text[i] == '\n' {
			line, column = line+1, 1
			i++
			continue
		}
		_, n := utf8.DecodeRuneInString(s.Text[i:])
		if n == 0 {
			n = 1
		}
		if i+n > offset {
			break
		}
		i += n
		column++
	}
	return line, column
}
