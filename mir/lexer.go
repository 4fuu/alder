package mir

import (
	"fmt"
	"strconv"
	"strings"
)

// tokenKind classifies a lexical token.
type tokenKind uint8

const (
	tokEOF tokenKind = iota
	tokIdent
	tokAtName
	tokPercent
	tokInt
	tokFloat
	tokString
	tokPunct
)

// token is one lexical token with its source position. bol reports whether
// the token is the first token on its line; statements must start at a line
// start so that optional trailing operands (for example a unit return) are
// unambiguous.
type token struct {
	kind tokenKind
	text string
	line int
	col  int
	bol  bool
}

func (t *token) describe() string {
	switch t.kind {
	case tokEOF:
		return "end of input"
	case tokString:
		return "a string literal"
	case tokPunct:
		return fmt.Sprintf("%q", t.text)
	}
	return fmt.Sprintf("%q", t.text)
}

type lexer struct {
	src  string
	pos  int
	line int
	col  int
	bol  bool // the next token starts a new line
}

// lex tokenizes the whole input. '#' starts a line comment that runs to the
// end of the line. Errors are deterministic and carry line and column numbers.
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

func (l *lexer) peekByte() (byte, bool) {
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
		l.bol = true
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

func (l *lexer) next() (token, error) {
	for {
		c, ok := l.peekByte()
		if !ok {
			return token{kind: tokEOF, line: l.line, col: l.col}, nil
		}
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			l.advance()
		case c == '#':
			for {
				c, ok := l.peekByte()
				if !ok || c == '\n' {
					break
				}
				l.advance()
			}
		default:
			t, err := l.lexToken()
			if err != nil {
				return token{}, err
			}
			t.bol = l.bol
			l.bol = false
			return t, nil
		}
	}
}

func (l *lexer) lexToken() (token, error) {
	line, col := l.line, l.col
	c, _ := l.peekByte()
	switch {
	case isIdentStart(c):
		name, err := l.lexDottedName(line, col)
		if err != nil {
			return token{}, err
		}
		return token{kind: tokIdent, text: name, line: line, col: col}, nil
	case c == '@':
		l.advance()
		name, err := l.lexDottedName(line, col)
		if err != nil {
			return token{}, err
		}
		return token{kind: tokAtName, text: name, line: line, col: col}, nil
	case c == '%':
		l.advance()
		c, ok := l.peekByte()
		if !ok || !isIdentStart(c) {
			return token{}, l.errf(line, col, "expected a name after '%%'")
		}
		var b strings.Builder
		for {
			c, ok := l.peekByte()
			if !ok || !isIdentCont(c) {
				break
			}
			b.WriteByte(l.advance())
		}
		return token{kind: tokPercent, text: b.String(), line: line, col: col}, nil
	case c == '-' || isDigit(c):
		if c == '-' && l.pos+1 < len(l.src) && l.src[l.pos+1] == '>' {
			l.advance()
			l.advance()
			return token{kind: tokPunct, text: "->", line: line, col: col}, nil
		}
		return l.lexNumber(line, col)
	case c == '"':
		return l.lexString(line, col)
	case strings.ContainsRune("(){}:,=", rune(c)):
		l.advance()
		return token{kind: tokPunct, text: string(c), line: line, col: col}, nil
	}
	return token{}, l.errf(line, col, "unexpected character %q", string(c))
}

// lexDottedName consumes an identifier with optional dot-separated segments
// (for example "domain.destroy"). A trailing dot is an error.
func (l *lexer) lexDottedName(line, col int) (string, error) {
	var b strings.Builder
	b.WriteByte(l.advance()) // first character is an ident start
	for {
		c, ok := l.peekByte()
		if !ok {
			return b.String(), nil
		}
		if isIdentCont(c) {
			b.WriteByte(l.advance())
			continue
		}
		if c == '.' {
			l.advance()
			c2, ok := l.peekByte()
			if !ok || !isIdentStart(c2) {
				return "", l.errf(line, col, "dotted name %q has an incomplete segment", b.String())
			}
			b.WriteByte('.')
			b.WriteByte(l.advance())
			continue
		}
		return b.String(), nil
	}
}

func (l *lexer) lexNumber(line, col int) (token, error) {
	var b strings.Builder
	if c, _ := l.peekByte(); c == '-' {
		b.WriteByte(l.advance())
		c, ok := l.peekByte()
		if !ok || !isDigit(c) {
			return token{}, l.errf(line, col, "unexpected character %q", string(c))
		}
	}
	isFloat := false
	for {
		c, ok := l.peekByte()
		if !ok || !isDigit(c) {
			break
		}
		b.WriteByte(l.advance())
	}
	if c, ok := l.peekByte(); ok && c == '.' {
		isFloat = true
		b.WriteByte(l.advance())
		for {
			c, ok := l.peekByte()
			if !ok || !isDigit(c) {
				break
			}
			b.WriteByte(l.advance())
		}
	}
	if c, ok := l.peekByte(); ok && (c == 'e' || c == 'E') {
		b.WriteByte(l.advance())
		if c, ok := l.peekByte(); ok && (c == '+' || c == '-') {
			b.WriteByte(l.advance())
		}
		digits := 0
		for {
			c, ok := l.peekByte()
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
	var b strings.Builder
	b.WriteByte(l.advance()) // opening quote
	for {
		c, ok := l.peekByte()
		if !ok || c == '\n' {
			return token{}, l.errf(line, col, "unterminated string literal")
		}
		if c == '"' {
			b.WriteByte(l.advance())
			break
		}
		if c == '\\' {
			b.WriteByte(l.advance())
			c2, ok := l.peekByte()
			if !ok || c2 == '\n' {
				return token{}, l.errf(line, col, "unterminated string literal")
			}
			b.WriteByte(l.advance())
			continue
		}
		b.WriteByte(l.advance())
	}
	decoded, err := strconv.Unquote(b.String())
	if err != nil {
		return token{}, l.errf(line, col, "invalid string literal: %v", err)
	}
	return token{kind: tokString, text: decoded, line: line, col: col}, nil
}
