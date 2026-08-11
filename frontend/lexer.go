// Package frontend is the Go Stage 0 Aster compiler: deterministic source
// text -> fully typed and monomorphized program -> verified MIR 1 -> C11.
//
// The pipeline is strict: type inference and monomorphization complete
// before any backend MIR exists, and lowered MIR is never repaired. A
// program whose lowered MIR fails the verifier is a frontend bug.
package frontend

import (
	"fmt"
	"strconv"
	"strings"
)

// tokenKind classifies a source token.
type tokenKind uint8

const (
	tokEOF tokenKind = iota
	tokIdent
	tokInt
	tokFloat
	tokStr
	tokPunct
)

// keyword is a reserved word. Reserved words are never identifiers.
type keyword uint8

const (
	kwNone keyword = iota
	kwImport
	kwType
	kwEnum
	kwFn
	kwLet
	kwVar
	kwIf
	kwElse
	kwWhile
	kwFor
	kwIn
	kwReturn
	kwMatch
	kwUsing
	kwWith
	kwTry
	kwTrue
	kwFalse
	kwUnsafe
)

// keywordText mirrors the keyword list in order.
var keywordText = [...]string{
	"", "import", "type", "enum", "fn", "let", "var", "if", "else",
	"while", "for", "in", "return", "match", "using", "with", "try",
	"true", "false", "unsafe",
}

// token is one source token with its position.
type token struct {
	kind tokenKind
	kw   keyword
	text string
	line int
	col  int
}

func (t *token) describe() string {
	switch t.kind {
	case tokEOF:
		return "end of input"
	case tokStr:
		return "a string literal"
	}
	return fmt.Sprintf("%q", t.text)
}

// lexer tokenizes a whole source file. Comments are // line comments and
// /* block comments */; block comments must terminate.
type lexer struct {
	src  string
	pos  int
	line int
	col  int
}

// lex runs the lexer to completion.
func lex(src string) ([]token, error) {
	l := &lexer{src: src, line: 1, col: 1}
	var toks []token
	for {
		t, err := l.next()
		if err != nil {
			return nil, err
		}
		toks = append(toks, t)
		if t.kind == tokEOF {
			return toks, nil
		}
	}
}

func (l *lexer) errf(line, col int, format string, args ...any) error {
	return fmt.Errorf("line %d, column %d: %s", line, col, fmt.Sprintf(format, args...))
}

func (l *lexer) peek() (byte, bool) {
	if l.pos >= len(l.src) {
		return 0, false
	}
	return l.src[l.pos], true
}

func (l *lexer) advance() byte {
	c := l.src[l.pos]
	l.pos++
	if c == '\n' {
		l.line++
		l.col = 1
	} else {
		l.col++
	}
	return c
}

func isIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isIdentCont(c byte) bool {
	return isIdentStart(c) || (c >= '0' && c <= '9')
}

func isDigit(c byte) bool {
	return c >= '0' && c <= '9'
}

// keywordOf maps an identifier to its keyword, if any.
func keywordOf(name string) keyword {
	for i := 1; i < len(keywordText); i++ {
		if keywordText[i] == name {
			return keyword(i)
		}
	}
	return kwNone
}

func (l *lexer) next() (token, error) {
	for {
		c, ok := l.peek()
		if !ok {
			return token{kind: tokEOF, line: l.line, col: l.col}, nil
		}
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			l.advance()
		case c == '/' && l.pos+1 < len(l.src) && l.src[l.pos+1] == '/':
			for {
				c, ok := l.peek()
				if !ok || c == '\n' {
					break
				}
				l.advance()
			}
		case c == '/' && l.pos+1 < len(l.src) && l.src[l.pos+1] == '*':
			line, col := l.line, l.col
			l.advance()
			l.advance()
			closed := false
			for {
				c, ok := l.peek()
				if !ok {
					return token{}, l.errf(line, col, "unterminated block comment")
				}
				if c == '*' && l.pos+1 < len(l.src) && l.src[l.pos+1] == '/' {
					l.advance()
					l.advance()
					closed = true
					break
				}
				l.advance()
			}
			_ = closed
		default:
			return l.lexToken()
		}
	}
}

func (l *lexer) lexToken() (token, error) {
	line, col := l.line, l.col
	c, _ := l.peek()
	switch {
	case isIdentStart(c):
		var b strings.Builder
		for {
			c, ok := l.peek()
			if !ok || !isIdentCont(c) {
				break
			}
			b.WriteByte(l.advance())
		}
		name := b.String()
		if kw := keywordOf(name); kw != kwNone {
			return token{kind: tokIdent, kw: kw, text: name, line: line, col: col}, nil
		}
		return token{kind: tokIdent, text: name, line: line, col: col}, nil

	case c == '-' && l.pos+1 < len(l.src) && l.src[l.pos+1] == '>':
		l.advance()
		l.advance()
		return token{kind: tokPunct, text: "->", line: line, col: col}, nil

	case c == '-' && l.pos+1 < len(l.src) && isDigit(l.src[l.pos+1]):
		return l.lexNumber(line, col)

	case c == '-' || isDigit(c):
		// A bare '-' is punctuation (unary minus); a '-' followed by a
		// digit was handled above as part of a negative literal.
		if c == '-' {
			break
		}
		return l.lexNumber(line, col)

	case c == '"':
		return l.lexString(line, col)

	case strings.ContainsRune("(){}[],:;=.<>!&|+-*/%", rune(c)):
		if c == ';' {
			return token{}, l.errf(line, col, "semicolons are not allowed; end the statement with a line break or \"}\"")
		}
		// Multi-character operators: -> << >> == != <= >= && ||.
		two := ""
		if l.pos+1 < len(l.src) {
			two = string(c) + string(l.src[l.pos+1])
		}
		switch two {
		case "->", "<<", ">>", "==", "!=", "<=", ">=", "&&", "||", "=>":
			l.advance()
			l.advance()
			return token{kind: tokPunct, text: two, line: line, col: col}, nil
		}
		l.advance()
		return token{kind: tokPunct, text: string(c), line: line, col: col}, nil
	}
	return token{}, l.errf(line, col, "unexpected character %q", string(c))
}

func (l *lexer) lexNumber(line, col int) (token, error) {
	var b strings.Builder
	if c, _ := l.peek(); c == '-' {
		b.WriteByte(l.advance())
		c, ok := l.peek()
		if !ok || !isDigit(c) {
			return token{}, l.errf(line, col, "unexpected character %q", string(c))
		}
	}
	isFloat := false
	for {
		c, ok := l.peek()
		if !ok || !isDigit(c) {
			break
		}
		b.WriteByte(l.advance())
	}
	if c, ok := l.peek(); ok && c == '.' {
		isFloat = true
		b.WriteByte(l.advance())
		for {
			c, ok := l.peek()
			if !ok || !isDigit(c) {
				break
			}
			b.WriteByte(l.advance())
		}
	}
	if c, ok := l.peek(); ok && (c == 'e' || c == 'E') {
		b.WriteByte(l.advance())
		if c, ok := l.peek(); ok && (c == '+' || c == '-') {
			b.WriteByte(l.advance())
		}
		digits := 0
		for {
			c, ok := l.peek()
			if !ok || !isDigit(c) {
				break
			}
			digits++
			b.WriteByte(l.advance())
		}
		if digits == 0 {
			return token{}, l.errf(line, col, "invalid number %q", b.String())
		}
		isFloat = true
	}
	kind := tokInt
	if isFloat {
		kind = tokFloat
	}
	return token{kind: kind, text: b.String(), line: line, col: col}, nil
}

func (l *lexer) lexString(line, col int) (token, error) {
	l.advance() // opening quote
	var b strings.Builder
	for {
		c, ok := l.peek()
		if !ok || c == '\n' {
			return token{}, l.errf(line, col, "unterminated string literal")
		}
		if c == '"' {
			l.advance()
			break
		}
		if c == '\\' {
			l.advance()
			c2, ok := l.peek()
			if !ok || c2 == '\n' {
				return token{}, l.errf(line, col, "unterminated string literal")
			}
			l.advance()
			switch c2 {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			case '\\':
				b.WriteByte('\\')
			case '"':
				b.WriteByte('"')
			case '0':
				b.WriteByte(0)
			default:
				return token{}, l.errf(line, col, "invalid escape \\%s", string(c2))
			}
			continue
		}
		b.WriteByte(l.advance())
	}
	return token{kind: tokStr, text: b.String(), line: line, col: col}, nil
}

// parseIntLiteral parses a decimal integer literal into an int64 value and
// reports whether it overflows int64 (values up to 2^63 are tracked for the
// negated INT64_MIN form).
func parseIntLiteral(text string) (int64, bool) {
	neg := strings.HasPrefix(text, "-")
	magText := strings.TrimPrefix(text, "-")
	mag, err := strconv.ParseUint(magText, 10, 64)
	if err != nil {
		return 0, true
	}
	if mag > 1<<63 {
		return 0, true
	}
	if neg {
		if mag == 1<<63 {
			return -9223372036854775808, false
		}
		return -int64(mag), false
	}
	return int64(mag), false
}
