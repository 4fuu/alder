package mir

import (
	"fmt"
	"strconv"
	"strings"
)

// parser builds a Module from the textual MIR format. Names resolve to stable
// numeric IDs as they are parsed. Function headers are predeclared; all other
// declarations must precede uses.
type parser struct {
	m    *Module
	toks []token
	pos  int

	fn       *Function
	curBlock *Block
	values   map[string]ValueId
	locals   map[string]LocalId
	blocks   map[string]BlockId

	typeLimit   int
	constLimit  int
	importLimit int
	inBody      bool
}

type functionBody struct {
	f           *Function
	start       int
	typeLimit   int
	constLimit  int
	importLimit int
}

// Parse parses the versioned textual MIR format. Errors are deterministic and
// carry line and column numbers.
func Parse(text string) (*Module, error) {
	toks, err := lex(text)
	if err != nil {
		return nil, err
	}
	p := &parser{m: NewModule(), toks: toks}
	if err := p.parseModule(); err != nil {
		return nil, err
	}
	return p.m, nil
}

// --- token helpers ---

func (p *parser) peek() *token {
	return &p.toks[p.pos]
}

func (p *parser) peekAt(n int) *token {
	i := p.pos + n
	if i >= len(p.toks) {
		return &p.toks[len(p.toks)-1]
	}
	return &p.toks[i]
}

func (p *parser) next() *token {
	t := &p.toks[p.pos]
	if t.kind != tokEOF {
		p.pos++
	}
	return t
}

func (p *parser) errf(t *token, format string, args ...any) error {
	return fmt.Errorf("line %d, column %d: %s", t.line, t.col, fmt.Sprintf(format, args...))
}

func (p *parser) expectPunct(text string) error {
	t := p.next()
	if t.kind != tokPunct || t.text != text {
		return p.errf(t, "expected %q, got %s", text, t.describe())
	}
	return nil
}

func (p *parser) expectComma() error {
	return p.expectPunct(",")
}

func (p *parser) expectIdent(what string) (*token, error) {
	t := p.next()
	if t.kind != tokIdent {
		return nil, p.errf(t, "expected %s, got %s", what, t.describe())
	}
	return t, nil
}

func (p *parser) expectAtName(what string) (*token, error) {
	t := p.next()
	if t.kind != tokAtName {
		return nil, p.errf(t, "expected %s, got %s", what, t.describe())
	}
	return t, nil
}

func (p *parser) peekIdent(text string) bool {
	t := p.peek()
	return t.kind == tokIdent && t.text == text
}

// --- module-level declarations ---

func (p *parser) parseModule() error {
	t := p.next()
	if t.kind != tokIdent || t.text != "mir" {
		return p.errf(t, "expected 'mir <version>'")
	}
	vt := p.next()
	if vt.kind != tokInt {
		return p.errf(vt, "expected a format version number")
	}
	n, err := strconv.Atoi(vt.text)
	if err != nil {
		return p.errf(vt, "invalid format version %q", vt.text)
	}
	if n < LegacyFormatVersion || n > CurrentFormatVersion {
		return p.errf(vt, "unsupported format version %d (supported: 1, 2, 3, 4)", n)
	}
	p.m.FormatVersion = n

	var bodies []functionBody
	for {
		t := p.peek()
		if t.kind == tokEOF {
			break
		}
		if t.kind != tokIdent {
			return p.errf(t, "expected a declaration, got %s", t.describe())
		}
		switch t.text {
		case "type":
			p.next()
			if err := p.parseTypeDecl(); err != nil {
				return err
			}
		case "enum":
			p.next()
			if err := p.parseEnumDecl(); err != nil {
				return err
			}
		case "const":
			p.next()
			if err := p.parseConstDecl(); err != nil {
				return err
			}
		case "import":
			p.next()
			if err := p.parseImportDecl(); err != nil {
				return err
			}
		case "binding":
			p.next()
			if err := p.parseBindingDecl(); err != nil {
				return err
			}
		case "fn":
			p.next()
			body, err := p.parseFunctionHeader()
			if err != nil {
				return err
			}
			bodies = append(bodies, body)
		default:
			return p.errf(t, "expected a declaration, got %q", t.text)
		}
	}
	for _, body := range bodies {
		p.pos = body.start
		p.typeLimit = body.typeLimit
		p.constLimit = body.constLimit
		p.importLimit = body.importLimit
		p.inBody = true
		if err := p.parseFunctionBody(body.f); err != nil {
			return err
		}
	}
	return nil
}

func (p *parser) parseTypeDecl() error {
	nameTok, err := p.expectAtName("a type name")
	if err != nil {
		return err
	}
	if _, ok := p.m.NamedType(nameTok.text); ok {
		return p.errf(nameTok, "duplicate type @%s", nameTok.text)
	}
	if err := p.expectPunct("{"); err != nil {
		return err
	}
	var fields []Field
	for {
		if p.peek().kind == tokPunct && p.peek().text == "}" {
			p.next()
			break
		}
		nameTok, err := p.expectIdent("a field name")
		if err != nil {
			return err
		}
		if err := p.expectPunct(":"); err != nil {
			return err
		}
		typ, err := p.parseType()
		if err != nil {
			return err
		}
		fields = append(fields, Field{Name: nameTok.text, Type: typ})
	}
	p.m.AddAggregate(nameTok.text, fields)
	return nil
}

func (p *parser) parseEnumDecl() error {
	nameTok, err := p.expectAtName("an enum name")
	if err != nil {
		return err
	}
	if _, ok := p.m.NamedType(nameTok.text); ok {
		return p.errf(nameTok, "duplicate type @%s", nameTok.text)
	}
	if err := p.expectPunct("{"); err != nil {
		return err
	}
	var variants []Variant
	for {
		if p.peek().kind == tokPunct && p.peek().text == "}" {
			p.next()
			break
		}
		nameTok, err := p.expectIdent("a variant name")
		if err != nil {
			return err
		}
		if nameTok.text == "default" {
			return p.errf(nameTok, "variant name %q is reserved", nameTok.text)
		}
		payload := TypeUnit
		if p.peek().kind == tokPunct && p.peek().text == "(" {
			p.next()
			payload, err = p.parseType()
			if err != nil {
				return err
			}
			if err := p.expectPunct(")"); err != nil {
				return err
			}
		}
		variants = append(variants, Variant{Name: nameTok.text, Payload: payload})
	}
	p.m.AddEnum(nameTok.text, variants)
	return nil
}

func (p *parser) parseConstDecl() error {
	nameTok, err := p.expectAtName("a constant name")
	if err != nil {
		return err
	}
	if _, ok := p.m.ConstDecl(nameTok.text); ok {
		return p.errf(nameTok, "duplicate constant @%s", nameTok.text)
	}
	if err := p.expectPunct(":"); err != nil {
		return err
	}
	typ, err := p.parseType()
	if err != nil {
		return err
	}
	if err := p.expectPunct("="); err != nil {
		return err
	}
	val, err := p.parseConstValueFor(typ)
	if err != nil {
		return err
	}
	p.m.AddConst(nameTok.text, typ, val)
	return nil
}

// parseConstValueFor parses a constant value with its declared type in
// scope. A u64 constant is printed as the unsigned decimal of its 64-bit
// pattern, which may exceed the signed int64 range, so such a token is read
// as an unsigned integer and stored as the equivalent bit pattern. A float
// constant is printed in Go's shortest 'g' form, which writes integral
// values without a decimal point ("1.0" prints as "1"), so an integer token
// under a float declared type reads as that float value.
func (p *parser) parseConstValueFor(t TypeId) (ConstValue, error) {
	if t == TypeU64 && p.peek().kind == tokInt {
		if _, err := strconv.ParseInt(p.peek().text, 10, 64); err != nil {
			tok := p.next()
			u, uerr := strconv.ParseUint(tok.text, 10, 64)
			if uerr != nil {
				return ConstValue{}, p.errf(tok, "integer literal %q out of range", tok.text)
			}
			return ConstValue{Kind: ConstInt, Int: int64(u)}, nil
		}
	}
	if IsFloatType(t) && p.peek().kind == tokInt {
		tok := p.next()
		f, err := strconv.ParseFloat(tok.text, 64)
		if err != nil {
			return ConstValue{}, p.errf(tok, "float literal %q out of range", tok.text)
		}
		return ConstValue{Kind: ConstFloat, Float: f}, nil
	}
	return p.parseConstValue()
}

func (p *parser) parseConstValue() (ConstValue, error) {
	t := p.next()
	switch t.kind {
	case tokInt:
		n, err := strconv.ParseInt(t.text, 10, 64)
		if err != nil {
			return ConstValue{}, p.errf(t, "integer literal %q out of range", t.text)
		}
		return ConstValue{Kind: ConstInt, Int: n}, nil
	case tokFloat:
		f, err := strconv.ParseFloat(t.text, 64)
		if err != nil {
			return ConstValue{}, p.errf(t, "float literal %q out of range", t.text)
		}
		return ConstValue{Kind: ConstFloat, Float: f}, nil
	case tokString:
		return ConstValue{Kind: ConstString, String: t.text}, nil
	case tokIdent:
		switch t.text {
		case "true":
			return ConstValue{Kind: ConstBool, Bool: true}, nil
		case "false":
			return ConstValue{Kind: ConstBool, Bool: false}, nil
		}
	case tokPunct:
		if t.text == "(" && p.peek().kind == tokPunct && p.peek().text == ")" {
			p.next()
			return ConstValue{Kind: ConstUnit}, nil
		}
	}
	return ConstValue{}, p.errf(t, "expected a constant value, got %s", t.describe())
}

func (p *parser) parseImportDecl() error {
	nameTok, err := p.expectAtName("an import name")
	if err != nil {
		return err
	}
	if _, ok := p.m.Import(nameTok.text); ok {
		return p.errf(nameTok, "duplicate import @%s", nameTok.text)
	}
	if err := p.expectPunct(":"); err != nil {
		return err
	}
	sig, err := p.parseFuncSig()
	if err != nil {
		return err
	}
	p.m.AddImport(nameTok.text, sig)
	return nil
}

func (p *parser) expectString(what string) (*token, error) {
	t := p.next()
	if t.kind != tokString {
		return nil, p.errf(t, "expected %s, got %s", what, t.describe())
	}
	return t, nil
}

// parseBindingDecl parses one C binding block:
//
//	binding @name "header" {
//	    c_type opaque @File = "FILE"
//	    c_type scalar @Time = "time_t"
//	    c_type record @Timespec = "struct timespec" { seconds: @Time = "tv_sec" }
//	    c_fn @open = "fopen"(c_const_ptr(c_char)) -> c_ptr(@File)
//	    c_const @X = "X": c_int
//	}
//
// The `= "spelling"` form is optional for functions and constants; the
// spelling then duplicates the Alder name. Type members always spell it.
func (p *parser) parseBindingDecl() error {
	if p.m.FormatVersion < BindingFormatVersion {
		return p.errf(p.peek(), "binding blocks require MIR format version 6")
	}
	nameTok, err := p.expectAtName("a binding name")
	if err != nil {
		return err
	}
	for i := range p.m.Bindings {
		if p.m.Bindings[i].Name == nameTok.text {
			return p.errf(nameTok, "duplicate binding @%s", nameTok.text)
		}
	}
	headerTok, err := p.expectString("a quoted header path")
	if err != nil {
		return err
	}
	if err := p.expectPunct("{"); err != nil {
		return err
	}
	blockIdx := p.m.AddBinding(nameTok.text, headerTok.text)
	block := &p.m.Bindings[blockIdx]
	for {
		t := p.peek()
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			return nil
		}
		if t.kind != tokIdent {
			return p.errf(t, "expected a binding member or '}', got %s", t.describe())
		}
		switch t.text {
		case "c_type":
			p.next()
			if err := p.parseBindingType(block); err != nil {
				return err
			}
		case "c_fn":
			p.next()
			if err := p.parseBindingFunc(block); err != nil {
				return err
			}
		case "c_const":
			p.next()
			if err := p.parseBindingConst(block); err != nil {
				return err
			}
		default:
			return p.errf(t, "expected a binding member, got %q", t.text)
		}
	}
}

// spelledName returns the C spelling for a member: the explicit string when
// the `= "..."` form is present, or the member name when omitted. The second
// result reports whether the spelling was spelled explicitly.
func (p *parser) spelledName(nameTok *token) (string, bool, error) {
	if p.peek().kind == tokPunct && p.peek().text == "=" {
		p.next()
		tok, err := p.expectString("a quoted C spelling")
		if err != nil {
			return "", false, err
		}
		return tok.text, true, nil
	}
	return nameTok.text, false, nil
}

func (p *parser) parseBindingType(block *BindingBlock) error {
	classTok := p.peek()
	if classTok.kind != tokIdent {
		return p.errf(classTok, "expected a binding type class, got %s", classTok.describe())
	}
	var class CClass
	switch classTok.text {
	case "scalar":
		class = CClassScalar
	case "opaque":
		class = CClassOpaque
	case "record":
		class = CClassRecord
	default:
		return p.errf(classTok, "unknown binding type class %q", classTok.text)
	}
	p.next()
	nameTok, err := p.expectAtName("a binding type name")
	if err != nil {
		return err
	}
	if _, ok := p.m.NamedType(nameTok.text); ok {
		return p.errf(nameTok, "duplicate type @%s", nameTok.text)
	}
	spelling, _, err := p.spelledName(nameTok)
	if err != nil {
		return err
	}
	var fields []Field
	if class == CClassRecord {
		if err := p.expectPunct("{"); err != nil {
			return err
		}
		for {
			if p.peek().kind == tokPunct && p.peek().text == "}" {
				p.next()
				break
			}
			fieldTok, err := p.expectIdent("a record field name")
			if err != nil {
				return err
			}
			if err := p.expectPunct(":"); err != nil {
				return err
			}
			typ, err := p.parseType()
			if err != nil {
				return err
			}
			fieldSpelling, _, err := p.spelledName(fieldTok)
			if err != nil {
				return err
			}
			for _, f := range fields {
				if f.Name == fieldTok.text {
					return p.errf(fieldTok, "duplicate record field %q", fieldTok.text)
				}
			}
			fields = append(fields, Field{Name: fieldTok.text, Type: typ, CName: fieldSpelling})
			if p.peek().kind == tokPunct && p.peek().text == "," {
				p.next()
			}
		}
	}
	id := p.m.AddCNamed(nameTok.text, spelling, class, fields)
	block.Types = append(block.Types, id)
	return nil
}

func (p *parser) parseBindingFunc(block *BindingBlock) error {
	nameTok, err := p.expectAtName("a binding function name")
	if err != nil {
		return err
	}
	for _, f := range block.Funcs {
		if f.Name == nameTok.text {
			return p.errf(nameTok, "duplicate binding function @%s", nameTok.text)
		}
	}
	spelling, _, err := p.spelledName(nameTok)
	if err != nil {
		return err
	}
	if err := p.expectPunct("("); err != nil {
		return err
	}
	var params []TypeId
	for {
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			p.next()
			break
		}
		typ, err := p.parseType()
		if err != nil {
			return err
		}
		params = append(params, typ)
		if p.peek().kind == tokPunct && p.peek().text == "," {
			p.next()
		}
	}
	if err := p.expectPunct("->"); err != nil {
		return err
	}
	result, err := p.parseType()
	if err != nil {
		return err
	}
	block.Funcs = append(block.Funcs, BindingFunc{Name: nameTok.text, CName: spelling, Sig: FuncSig{Params: params, Result: result, Env: NoType}})
	return nil
}

func (p *parser) parseBindingConst(block *BindingBlock) error {
	nameTok, err := p.expectAtName("a binding constant name")
	if err != nil {
		return err
	}
	for _, c := range block.Consts {
		if c.Name == nameTok.text {
			return p.errf(nameTok, "duplicate binding constant @%s", nameTok.text)
		}
	}
	spelling, _, err := p.spelledName(nameTok)
	if err != nil {
		return err
	}
	if err := p.expectPunct(":"); err != nil {
		return err
	}
	typ, err := p.parseType()
	if err != nil {
		return err
	}
	block.Consts = append(block.Consts, BindingConst{Name: nameTok.text, CName: spelling, Type: typ})
	return nil
}

// parseFuncSig parses "fn(params) -> result".
func (p *parser) parseFuncSig() (FuncSig, error) {
	t, err := p.expectIdent("'fn'")
	if err != nil {
		return FuncSig{}, err
	}
	if t.text != "fn" {
		return FuncSig{}, p.errf(t, "expected 'fn', got %q", t.text)
	}
	if err := p.expectPunct("("); err != nil {
		return FuncSig{}, err
	}
	var sig FuncSig
	sig.Env = NoType
	for {
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			p.next()
			break
		}
		typ, err := p.parseType()
		if err != nil {
			return FuncSig{}, err
		}
		sig.Params = append(sig.Params, typ)
		if p.peek().kind == tokPunct && p.peek().text == "," {
			p.next()
			continue
		}
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			p.next()
			break
		}
		return FuncSig{}, p.errf(p.peek(), "expected ',' or ')' in function signature")
	}
	if err := p.expectPunct("->"); err != nil {
		return FuncSig{}, err
	}
	sig.Result, err = p.parseType()
	if err != nil {
		return FuncSig{}, err
	}
	if p.peek().kind == tokPunct && p.peek().text == "," {
		if p.m.FormatVersion < ClosureFormatVersion {
			return FuncSig{}, p.errf(p.peek(), "function environment requires MIR format version %d", ClosureFormatVersion)
		}
		p.next()
		env, err := p.parseType()
		if err != nil {
			return FuncSig{}, err
		}
		sig.Env = env
	}
	return sig, nil
}

// --- functions ---

func (p *parser) parseFunctionHeader() (functionBody, error) {
	nameTok, err := p.expectAtName("a function name")
	if err != nil {
		return functionBody{}, err
	}
	if _, ok := p.m.Function(nameTok.text); ok {
		return functionBody{}, p.errf(nameTok, "duplicate function @%s", nameTok.text)
	}
	if err := p.expectPunct("("); err != nil {
		return functionBody{}, err
	}
	params, err := p.parseParams()
	if err != nil {
		return functionBody{}, err
	}
	if err := p.expectPunct(")"); err != nil {
		return functionBody{}, err
	}
	result := TypeUnit
	if p.peek().kind == tokPunct && p.peek().text == "->" {
		p.next()
		result, err = p.parseType()
		if err != nil {
			return functionBody{}, err
		}
	}
	if err := p.expectPunct("{"); err != nil {
		return functionBody{}, err
	}

	f := p.m.AddFunction(nameTok.text, params, result)
	body := functionBody{f: f, start: p.pos, typeLimit: len(p.m.Types), constLimit: len(p.m.Constants), importLimit: len(p.m.Imports)}
	depth := 0
	for {
		t := p.next()
		if t.kind == tokEOF {
			return functionBody{}, p.errf(t, "unterminated function body")
		}
		if t.kind != tokPunct {
			continue
		}
		switch t.text {
		case "{":
			depth++
		case "}":
			if depth == 0 {
				return body, nil
			}
			depth--
		}
	}
}

func (p *parser) parseFunctionBody(f *Function) error {
	p.fn = f
	p.values = make(map[string]ValueId)
	p.locals = make(map[string]LocalId)
	p.blocks = make(map[string]BlockId)
	p.curBlock = nil
	for i, prm := range f.Params {
		p.values[prm.Name] = ValueId(i)
	}

	// Register all block headers up front so forward block references resolve.
	if err := p.prescanBlocks(); err != nil {
		return err
	}

	for p.peekIdent("local") {
		if !p.peek().bol {
			return p.errf(p.peek(), "local declaration must start on a new line")
		}
		p.next()
		nameTok, err := p.expectPercent("a local name")
		if err != nil {
			return err
		}
		if _, ok := p.locals[nameTok.text]; ok {
			return p.errf(nameTok, "duplicate local %%%s", nameTok.text)
		}
		if err := p.expectPunct(":"); err != nil {
			return err
		}
		typ, err := p.parseType()
		if err != nil {
			return err
		}
		p.locals[nameTok.text] = f.AddLocal(nameTok.text, typ)
	}

	for {
		t := p.peek()
		if t.kind == tokEOF {
			return p.errf(t, "unterminated function body")
		}
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			break
		}
		switch {
		case t.kind == tokPercent:
			if err := p.parseInstrBound(); err != nil {
				return err
			}
		case t.kind == tokIdent:
			n := p.peekAt(1)
			if n.kind == tokPunct && (n.text == "(" || n.text == ":") {
				if !t.bol {
					return p.errf(t, "block header must start on a new line")
				}
				if err := p.parseBlockHeader(); err != nil {
					return err
				}
			} else if err := p.parseInstrUnbound(); err != nil {
				return err
			}
		default:
			return p.errf(t, "expected an instruction, block header, or '}', got %s", t.describe())
		}
	}

	if p.curBlock != nil {
		return p.errf(p.peek(), "block %q has no terminator", p.curBlock.Name)
	}
	if len(f.Blocks) == 0 {
		return p.errf(p.peek(), "function must contain at least one block")
	}
	p.fn = nil
	p.curBlock = nil
	return nil
}

func (p *parser) expectPercent(what string) (*token, error) {
	t := p.next()
	if t.kind != tokPercent {
		return nil, p.errf(t, "expected %s, got %s", what, t.describe())
	}
	return t, nil
}

// prescanBlocks registers every block header of the function body before any
// body is parsed, so forward block references resolve immediately. Braced
// regions (switch bodies, aggregate.construct field lists) are skipped.
func (p *parser) prescanBlocks() error {
	depth := 0
	i := p.pos
	for i < len(p.toks) {
		t := &p.toks[i]
		if t.kind == tokPunct {
			switch t.text {
			case "{":
				depth++
			case "}":
				if depth == 0 {
					return nil // end of function body
				}
				depth--
			}
			i++
			continue
		}
		if t.kind == tokIdent && depth == 0 && t.bol {
			n := &p.toks[i+1]
			if n.kind == tokPunct && (n.text == "(" || n.text == ":") {
				if t.text == "else" {
					return p.errf(t, "block name %q is reserved", t.text)
				}
				if _, dup := p.blocks[t.text]; dup {
					return p.errf(t, "duplicate block %q", t.text)
				}
				i++
				if n.text == "(" {
					// Skip the parameter list to its matching ')'.
					d := 0
					for i < len(p.toks) {
						tk := &p.toks[i]
						if tk.kind == tokPunct {
							if tk.text == "(" {
								d++
							}
							if tk.text == ")" {
								d--
								if d == 0 {
									i++
									break
								}
							}
						}
						i++
					}
					if i >= len(p.toks) {
						return p.errf(t, "unterminated block header for %q", t.text)
					}
				}
				p.fn.AddBlock(t.text, nil)
				p.blocks[t.text] = BlockId(len(p.fn.Blocks) - 1)
				continue
			}
		}
		i++
	}
	return p.errf(p.peek(), "unterminated function body")
}

func (p *parser) parseBlockHeader() error {
	nameTok := p.next() // block name ident
	id, ok := p.blocks[nameTok.text]
	if !ok {
		return p.errf(nameTok, "internal error: unregistered block %q", nameTok.text)
	}
	var params []Param
	if p.peek().kind == tokPunct && p.peek().text == "(" {
		p.next()
		var err error
		params, err = p.parseParams()
		if err != nil {
			return err
		}
		if err := p.expectPunct(")"); err != nil {
			return err
		}
	}
	if err := p.expectPunct(":"); err != nil {
		return err
	}
	b := p.fn.Blocks[id]
	b.Params = params
	for i, prm := range params {
		if _, dup := p.values[prm.Name]; dup {
			return p.errf(nameTok, "duplicate value %%%s", prm.Name)
		}
		vid := p.fn.AddValue(prm.Name, prm.Type, ValueDef{Kind: ValueDefBlockParam, Block: id, Param: i})
		p.values[prm.Name] = vid
	}
	p.curBlock = b
	return nil
}

// parseParams parses "%name: type" pairs separated by commas, stopping at
// (but not consuming) the closing ')'.
func (p *parser) parseParams() ([]Param, error) {
	var params []Param
	for {
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			return params, nil
		}
		nameTok, err := p.expectPercent("a parameter name")
		if err != nil {
			return nil, err
		}
		if err := p.expectPunct(":"); err != nil {
			return nil, err
		}
		typ, err := p.parseType()
		if err != nil {
			return nil, err
		}
		params = append(params, Param{Name: nameTok.text, Type: typ})
		if p.peek().kind == tokPunct && p.peek().text == "," {
			p.next()
			continue
		}
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			return params, nil
		}
		return nil, p.errf(p.peek(), "expected ',' or ')' in parameter list")
	}
}

// --- instructions ---

func (p *parser) parseInstrBound() error {
	if !p.peek().bol {
		return p.errf(p.peek(), "instruction must start on a new line")
	}
	if p.curBlock == nil {
		return p.errf(p.peek(), "instruction outside a block or after a terminator")
	}
	nameTok := p.next() // %name
	if err := p.expectPunct("="); err != nil {
		return err
	}
	in, err := p.parseOp()
	if err != nil {
		return err
	}
	if !in.Op.ProducesResult() {
		return p.errf(nameTok, "operation %s produces no value", in.Op)
	}
	if _, dup := p.values[nameTok.text]; dup {
		return p.errf(nameTok, "duplicate value %%%s", nameTok.text)
	}
	typ, _ := p.m.InferResultType(p.fn, &in)
	vid := p.fn.AddValue(nameTok.text, typ, ValueDef{
		Kind:  ValueDefInstr,
		Block: p.blockID(p.curBlock),
		Instr: len(p.curBlock.Instrs),
	})
	p.values[nameTok.text] = vid
	in.Result = vid
	p.curBlock.AddInstr(in)
	return nil
}

func (p *parser) parseInstrUnbound() error {
	if !p.peek().bol {
		return p.errf(p.peek(), "instruction must start on a new line")
	}
	if p.curBlock == nil {
		return p.errf(p.peek(), "instruction outside a block or after a terminator")
	}
	t := p.peek()
	switch t.text {
	case "jump", "branch", "switch", "return", "fail", "panic", "unreachable":
		return p.parseTerminator()
	}
	in, err := p.parseOp()
	if err != nil {
		return err
	}
	if in.Op.ProducesResult() && !p.mayDropResult(&in) {
		return p.errf(t, "operation %s produces a value; bind it with '%%name = %s ...'", in.Op, in.Op)
	}
	p.curBlock.AddInstr(in)
	return nil
}

// mayDropResult reports whether a producing operation may be left unbound:
// calls and FFI calls whose callee or import result type is unit.
func (p *parser) mayDropResult(in *Instr) bool {
	switch in.Op {
	case OpCall:
		if int(in.Callee) < len(p.m.Functions) {
			return p.m.Functions[in.Callee].Result == TypeUnit
		}
	case OpFFICallUnsafe:
		if int(in.FFIImport) < len(p.m.Imports) {
			return p.m.Imports[in.FFIImport].Sig.Result == TypeUnit
		}
	case OpCBindingCall:
		_, fn, ok := p.m.BindingFuncAt(in.CBinding)
		if ok {
			return fn.Sig.Result == TypeUnit
		}
	}
	return false
}

func (p *parser) blockID(b *Block) BlockId {
	for i, blk := range p.fn.Blocks {
		if blk == b {
			return BlockId(i)
		}
	}
	return NoBlock
}

// parseOp parses an operation name and its operands. The optional 'else'
// failure edge is required for checked operations.
func (p *parser) parseOp() (Instr, error) {
	t := p.next() // operation name
	in := Instr{Result: NoValue, FailTarget: NoBlock}
	var err error
	if strings.HasPrefix(t.text, "vec.") && p.m.FormatVersion < VecFormatVersion {
		return in, p.errf(t, "%s requires MIR format version 4", t.text)
	}
	if t.text == "array.as_slice" && p.m.FormatVersion < VecFormatVersion {
		return in, p.errf(t, "%s requires MIR format version 4", t.text)
	}

	// Binary operations over two values with an optional required else edge.
	parseBinary := func(op OpKind) error {
		in.Op = op
		if in.A, err = p.parseValueRef(); err != nil {
			return err
		}
		if err = p.expectComma(); err != nil {
			return err
		}
		if in.B, err = p.parseValueRef(); err != nil {
			return err
		}
		if op.HasFailEdge() {
			return p.parseOptionalElse(t, &in)
		}
		return nil
	}
	// Operations with one value operand and an explicit result type operand.
	parseConv := func(op OpKind) error {
		in.Op = op
		if in.A, err = p.parseValueRef(); err != nil {
			return err
		}
		if err = p.expectComma(); err != nil {
			return err
		}
		if in.TypeOp, err = p.parseType(); err != nil {
			return err
		}
		return nil
	}

	switch t.text {
	case "load":
		in.Op = OpLoad
		in.Place, err = p.parsePlace()
	case "borrow":
		in.Op = OpBorrow
		in.Place, err = p.parsePlace()
	case "borrow_mut":
		in.Op = OpBorrowMut
		in.Place, err = p.parsePlace()

	case "store":
		in.Op = OpStore
		if in.Place, err = p.parsePlace(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.StoreVal, err = p.parseValueRef()

	case "aggregate.construct":
		in.Op = OpAggregateConstruct
		if in.AggType, err = p.parseType(); err != nil {
			return in, err
		}
		if err = p.expectPunct("{"); err != nil {
			return in, err
		}
		isArray := p.m.Types[in.AggType].Kind == TypeArray
		for {
			if p.peek().kind == tokPunct && p.peek().text == "}" {
				p.next()
				break
			}
			name := ""
			if !isArray {
				nameTok, err := p.expectIdent("a field name")
				if err != nil {
					return in, err
				}
				name = nameTok.text
				if err = p.expectPunct(":"); err != nil {
					return in, err
				}
			}
			val, err := p.parseValueRef()
			if err != nil {
				return in, err
			}
			in.AggFields = append(in.AggFields, AggField{Name: name, Value: val})
			if p.peek().kind == tokPunct && p.peek().text == "," {
				p.next()
			}
		}

	case "domain.create", "domain.mark", "domain.destroy":
		switch t.text {
		case "domain.create":
			in.Op = OpDomainCreate
		case "domain.mark":
			in.Op = OpDomainMark
		default:
			in.Op = OpDomainDestroy
		}
		in.Domain, err = p.parseValueRef()

	case "domain.reset":
		in.Op = OpDomainReset
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.Mark, err = p.parseValueRef()

	case "alloc", "alloc.checked":
		if t.text == "alloc.checked" {
			if p.m.FormatVersion < AllocCheckedFormatVersion {
				return in, p.errf(t, "alloc.checked requires MIR format version 3")
			}
			in.Op = OpAllocChecked
		} else {
			in.Op = OpAlloc
		}
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.TypeOp, err = p.parseType(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.Count, err = p.parseValueRef()
		if err == nil && in.Op == OpAllocChecked {
			err = p.parseOptionalElse(t, &in)
		}

	case "copy_to_domain":
		in.Op = OpCopyToDomain
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.CopyVal, err = p.parseValueRef()

	case "cleanup.scope.begin":
		in.Op = OpCleanupScopeBegin

	case "cleanup.push":
		in.Op = OpCleanupPush
		if in.Scope, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		fnTok := p.next()
		if fnTok.kind != tokAtName {
			return in, p.errf(fnTok, "expected a cleanup function, got %s", fnTok.describe())
		}
		id, ok := p.m.Function(fnTok.text)
		if !ok {
			return in, p.errf(fnTok, "unknown function @%s", fnTok.text)
		}
		in.CleanupFn = id
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if err = p.expectPunct("("); err != nil {
			return in, err
		}
		if in.CleanupArgs, err = p.parseArgs(); err != nil {
			return in, err
		}
		if err = p.expectPunct(")"); err != nil {
			return in, err
		}

	case "cleanup.disarm":
		in.Op = OpCleanupDisarm
		in.CleanupID, err = p.parseValueRef()

	case "cleanup.scope.run", "cleanup.scope.end":
		if t.text == "cleanup.scope.run" {
			in.Op = OpCleanupScopeRun
		} else {
			in.Op = OpCleanupScopeEnd
		}
		in.Scope, err = p.parseValueRef()

	case "int.add.checked", "int.sub.checked", "int.mul.checked", "int.div.checked", "int.shl.checked", "int.shr.checked":
		var op OpKind
		switch t.text {
		case "int.add.checked":
			op = OpIntAddChecked
		case "int.sub.checked":
			op = OpIntSubChecked
		case "int.mul.checked":
			op = OpIntMulChecked
		case "int.div.checked":
			op = OpIntDivChecked
		case "int.shl.checked":
			op = OpIntShlChecked
		default:
			op = OpIntShrChecked
		}
		err = parseBinary(op)

	case "int.add.try", "int.sub.try", "int.mul.try",
		"int.add.saturating", "int.sub.saturating", "int.mul.saturating",
		"int.add.wrapping", "int.sub.wrapping", "int.mul.wrapping":
		var op OpKind
		switch t.text {
		case "int.add.try":
			op = OpIntAddTry
		case "int.sub.try":
			op = OpIntSubTry
		case "int.mul.try":
			op = OpIntMulTry
		case "int.add.saturating":
			op = OpIntAddSaturating
		case "int.sub.saturating":
			op = OpIntSubSaturating
		case "int.mul.saturating":
			op = OpIntMulSaturating
		case "int.add.wrapping":
			op = OpIntAddWrapping
		case "int.sub.wrapping":
			op = OpIntSubWrapping
		default:
			op = OpIntMulWrapping
		}
		err = parseBinary(op)

	case "slice.len":
		in.Op = OpSliceLen
		in.Slice, err = p.parseValueRef()

	case "slice.index.checked":
		in.Op = OpSliceIndexChecked
		if in.Slice, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Index, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)

	case "array.index.checked":
		in.Op = OpArrayIndexChecked
		if in.Array, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Index, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)

	case "slice.range.checked":
		in.Op = OpSliceRangeChecked
		if in.Slice, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Lo, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Hi, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)

	case "vec.new":
		in.Op = OpVecNew
		in.TypeOp, err = p.parseType()
	case "vec.construct.checked":
		in.Op = OpVecConstructChecked
		if in.Slice, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Lo, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Capacity, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
	case "vec.grow.checked":
		in.Op = OpVecGrowChecked
		if in.Slice, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Capacity, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
	case "vec.len", "vec.capacity", "vec.storage", "vec.as_slice", "vec.as_mut_slice":
		switch t.text {
		case "vec.len":
			in.Op = OpVecLen
		case "vec.capacity":
			in.Op = OpVecCapacity
		case "vec.storage":
			in.Op = OpVecStorage
		case "vec.as_slice":
			in.Op = OpVecAsSlice
		default:
			in.Op = OpVecAsMutSlice
		}
		in.Slice, err = p.parseValueRef()
	case "array.as_slice":
		in.Op = OpArrayAsSlice
		in.Array, err = p.parseValueRef()

	case "enum.payload.checked":
		in.Op = OpEnumPayloadChecked
		if in.EnumValue, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		variantTok, err := p.expectIdent("a variant name")
		if err != nil {
			return in, err
		}
		in.Variant = variantTok.text
		err = p.parseOptionalElse(t, &in)

	case "enum.construct":
		in.Op = OpEnumConstruct
		if in.TypeOp, err = p.parseType(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		variantTok, err := p.expectIdent("a variant name")
		if err != nil {
			return in, err
		}
		in.Variant = variantTok.text
		if p.peek().kind == tokPunct && p.peek().text == "," {
			p.next()
			in.Payload, err = p.parseValueRef()
			if err != nil {
				return in, err
			}
		} else {
			in.Payload = NoValue
		}

	case "table.create":
		in.Op = OpTableCreate
		if in.TypeOp, err = p.parseType(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.Domain, err = p.parseValueRef()

	case "table.insert":
		in.Op = OpTableInsert
		if in.Table, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.TableVal, err = p.parseValueRef()

	case "table.insert.try":
		in.Op = OpTableInsertTry
		if in.Table, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.TableVal, err = p.parseValueRef()

	case "table.lookup", "table.lookup_mut", "table.remove":
		if t.text == "table.lookup" {
			in.Op = OpTableLookup
		} else if t.text == "table.lookup_mut" {
			in.Op = OpTableLookupMut
		} else {
			in.Op = OpTableRemove
		}
		if in.Table, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.ID, err = p.parseValueRef()

	case "table.view.end":
		in.Op = OpTableViewEnd
		in.View, err = p.parseValueRef()

	case "int.eq", "int.ne", "int.lt", "int.le", "int.gt", "int.ge",
		"float.eq", "float.ne", "float.lt", "float.le", "float.gt", "float.ge":
		op, ok := cmpOpByName[t.text]
		if !ok {
			return in, p.errf(t, "internal error: unknown comparison %q", t.text)
		}
		err = parseBinary(op)

	case "int.trunc", "int.zext", "int.sext", "float.convert", "int.from_float", "float.from_int",
		"int.convert.checked", "int.convert.wrap":
		op, ok := convOpByName[t.text]
		if !ok {
			return in, p.errf(t, "internal error: unknown conversion %q", t.text)
		}
		err = parseConv(op)

	case "c.num.try", "c.num.wrap", "c.num.cast":
		op, ok := cNumOpByName[t.text]
		if !ok {
			return in, p.errf(t, "internal error: unknown c conversion %q", t.text)
		}
		if p.m.FormatVersion < BindingFormatVersion {
			return in, p.errf(t, "%s requires MIR format version %d", t.text, BindingFormatVersion)
		}
		err = parseConv(op)

	case "float.add", "float.sub", "float.mul", "float.div":
		op, ok := floatArithOpByName[t.text]
		if !ok {
			return in, p.errf(t, "internal error: unknown float arithmetic %q", t.text)
		}
		err = parseBinary(op)

	case "int.and", "int.or", "int.xor":
		op, ok := bitwiseOpByName[t.text]
		if !ok {
			return in, p.errf(t, "internal error: unknown bitwise operation %q", t.text)
		}
		err = parseBinary(op)

	case "int.not":
		in.Op = OpIntNot
		in.A, err = p.parseValueRef()

	case "const.get":
		in.Op = OpConstGet
		nameTok, err := p.expectAtName("a constant name")
		if err != nil {
			return in, err
		}
		decl, ok := p.m.ConstDecl(nameTok.text)
		if !ok || (p.inBody && !p.constVisible(decl)) {
			return in, p.errf(nameTok, "unknown constant @%s", nameTok.text)
		}
		in.Const = nameTok.text

	case "call":
		in.Op = OpCall
		fnTok, err := p.expectAtName("a function name")
		if err != nil {
			return in, err
		}
		id, ok := p.m.Function(fnTok.text)
		if !ok {
			return in, p.errf(fnTok, "unknown function @%s", fnTok.text)
		}
		in.Callee = id
		if err = p.expectPunct("("); err != nil {
			return in, err
		}
		if in.Args, err = p.parseArgs(); err != nil {
			return in, err
		}
		err = p.expectPunct(")")

	case "call.value":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "call.value requires MIR format version %d", ClosureFormatVersion)
		}
		in.Op = OpCallValue
		in.A, err = p.parseValueRef()
		if err != nil {
			return in, err
		}
		if err = p.expectPunct("("); err != nil {
			return in, err
		}
		if in.Args, err = p.parseArgs(); err != nil {
			return in, err
		}
		if err = p.expectPunct(")"); err != nil {
			return in, err
		}
		return in, nil

	case "fn.value":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "fn.value requires MIR format version %d", ClosureFormatVersion)
		}
		in.Op = OpFnValue
		fnTok, err := p.expectAtName("a function name")
		if err != nil {
			return in, err
		}
		id, ok := p.m.Function(fnTok.text)
		if !ok {
			return in, p.errf(fnTok, "unknown function @%s", fnTok.text)
		}
		in.Callee = id
		in.A = NoValue
		if p.peek().kind == tokPunct && p.peek().text == "(" {
			p.next()
			if in.A, err = p.parseValueRef(); err != nil {
				return in, err
			}
			if err = p.expectPunct(")"); err != nil {
				return in, err
			}
		}
		if p.peek().text == "domain" {
			p.next()
			in.TypeOp = FnValueDomainMarker
		}
		return in, nil

	case "str.eq":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "str.eq requires MIR format version %d", ClosureFormatVersion)
		}
		in.Op = OpStrEq
		in.A, err = p.parseValueRef()
		if err != nil {
			return in, err
		}
		if err = p.expectPunct(","); err != nil {
			return in, err
		}
		in.B, err = p.parseValueRef()
		if err != nil {
			return in, err
		}
		return in, nil

	case "str.order_lt":
		in.Op = OpStrOrderLt
		in.A, err = p.parseValueRef()
		if err != nil {
			return in, err
		}
		if err = p.expectPunct(","); err != nil {
			return in, err
		}
		in.B, err = p.parseValueRef()
		if err != nil {
			return in, err
		}
		return in, nil

	case "str.display":
		in.Op = OpStrDisplay
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectPunct(","); err != nil {
			return in, err
		}
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
		return in, err

	case "str.len", "str.to_bytes":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "%s requires MIR format version %d", t.text, BindingFormatVersion)
		}
		in.Op = OpStrLen
		if t.text == "str.to_bytes" {
			in.Op = OpStrToBytes
		}
		in.A, err = p.parseValueRef()
		return in, err

	case "str.byte.checked":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "str.byte.checked requires MIR format version %d", BindingFormatVersion)
		}
		in.Op = OpStrByteChecked
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.B, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
		return in, err

	case "str.concat":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "str.concat requires MIR format version %d", BindingFormatVersion)
		}
		in.Op = OpStrConcat
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.B, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
		return in, err

	case "str.slice.checked":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "str.slice.checked requires MIR format version %d", BindingFormatVersion)
		}
		in.Op = OpStrSliceChecked
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Lo, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.Hi, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
		return in, err

	case "str.from_bytes":
		if p.m.FormatVersion < ClosureFormatVersion {
			return in, p.errf(t, "str.from_bytes requires MIR format version %d", BindingFormatVersion)
		}
		in.Op = OpStrFromBytes
		if in.Domain, err = p.parseValueRef(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		err = p.parseOptionalElse(t, &in)
		return in, err

	case "ffi.call.unsafe":
		in.Op = OpFFICallUnsafe
		impTok, err := p.expectAtName("an import name")
		if err != nil {
			return in, err
		}
		id, ok := p.m.Import(impTok.text)
		if !ok || (p.inBody && int(id) >= p.importLimit) {
			return in, p.errf(impTok, "unknown import @%s", impTok.text)
		}
		in.FFIImport = id
		if err = p.expectPunct("("); err != nil {
			return in, err
		}
		if in.Args, err = p.parseArgs(); err != nil {
			return in, err
		}
		err = p.expectPunct(")")

	case "c.call.unsafe":
		if p.m.FormatVersion < BindingFormatVersion {
			return in, p.errf(t, "c.call.unsafe requires MIR format version %d", BindingFormatVersion)
		}
		refTok, err := p.expectAtName("a binding function reference")
		if err != nil {
			return in, err
		}
		idx, ok := p.bindingFuncRef(refTok.text)
		if !ok {
			return in, p.errf(refTok, "unknown binding function @%s", refTok.text)
		}
		in.Op = OpCBindingCall
		in.CBinding = idx
		if err = p.expectPunct("("); err != nil {
			return in, err
		}
		if in.Args, err = p.parseArgs(); err != nil {
			return in, err
		}
		err = p.expectPunct(")")

	case "c.is_null":
		if p.m.FormatVersion < BindingFormatVersion {
			return in, p.errf(t, "c.is_null requires MIR format version %d", BindingFormatVersion)
		}
		in.Op = OpCIsNull
		in.A, err = p.parseValueRef()

	case "c.field.get", "c.field.set":
		if p.m.FormatVersion < BindingFormatVersion {
			return in, p.errf(t, "%s requires MIR format version %d", t.text, BindingFormatVersion)
		}
		fieldTok, fieldErr := p.expectIdent("a record field name")
		if fieldErr != nil {
			return in, fieldErr
		}
		in.CField = fieldTok.text
		if t.text == "c.field.get" {
			in.Op = OpCFieldGet
			if err = p.expectPunct("("); err != nil {
				return in, err
			}
			in.A, err = p.parseValueRef()
			if err != nil {
				return in, err
			}
			err = p.expectPunct(")")
			break
		}
		// The write form stores into a place holding the record, in the
		// same operand order as store: place first, then the value.
		in.Op = OpCFieldSet
		if in.Place, err = p.parsePlace(); err != nil {
			return in, err
		}
		if err = p.expectComma(); err != nil {
			return in, err
		}
		in.A, err = p.parseValueRef()

	case "c.string.make_lit", "c.string.make", "c.string.ptr", "c.string.release":
		if p.m.FormatVersion < BindingFormatVersion {
			return in, p.errf(t, "%s requires MIR format version %d", t.text, BindingFormatVersion)
		}
		switch t.text {
		case "c.string.make_lit":
			in.Op = OpCStringMakeLit
		case "c.string.make":
			in.Op = OpCStringMake
		case "c.string.ptr":
			in.Op = OpCStringPtr
		default:
			in.Op = OpCStringRelease
		}
		if in.A, err = p.parseValueRef(); err != nil {
			return in, err
		}
		// The constructors are checked: an interior-NUL scan or allocation
		// failure takes the explicit edge. ptr and release cannot fail.
		if in.Op == OpCStringMakeLit || in.Op == OpCStringMake {
			err = p.parseOptionalElse(t, &in)
		}

	default:
		return in, p.errf(t, "unknown operation %q", t.text)
	}
	return in, err
}

// bindingFuncRef resolves a "@block.function" name to the flattened
// block-major index of a binding function member.
func (p *parser) bindingFuncRef(text string) (int, bool) {
	dot := -1
	for i := 0; i < len(text); i++ {
		if text[i] == '.' {
			if dot != -1 {
				return 0, false
			}
			dot = i
		}
	}
	if dot <= 0 || dot == len(text)-1 {
		return 0, false
	}
	block, fn := text[:dot], text[dot+1:]
	index := 0
	for i := range p.m.Bindings {
		b := &p.m.Bindings[i]
		if b.Name != block {
			index += len(b.Funcs)
			continue
		}
		for j := range b.Funcs {
			if b.Funcs[j].Name == fn {
				return index + j, true
			}
		}
		return 0, false
	}
	return 0, false
}

// parseOptionalElse parses the mandatory 'else' failure edge of a checked
// operation. The edge must stay on the operation's line so that a block named
// 'else' on the next line is not consumed.
func (p *parser) parseOptionalElse(opTok *token, in *Instr) error {
	if p.peekIdent("else") && !p.peek().bol {
		p.next()
		args, err := p.parseBlockRef(&in.FailTarget)
		in.FailArgs = args
		return err
	}
	return p.errf(p.peek(), "operation %s requires an 'else' failure edge", opTok.text)
}

// parseBlockRef parses a block reference with optional edge arguments.
func (p *parser) parseBlockRef(dst *BlockId) ([]ValueId, error) {
	t := p.next()
	if t.kind != tokIdent {
		return nil, p.errf(t, "expected a block reference, got %s", t.describe())
	}
	id, ok := p.blocks[t.text]
	if !ok {
		return nil, p.errf(t, "unknown block %q", t.text)
	}
	*dst = id
	var args []ValueId
	if p.peek().kind == tokPunct && p.peek().text == "(" {
		p.next()
		var err error
		args, err = p.parseArgs()
		if err != nil {
			return nil, err
		}
		if err := p.expectPunct(")"); err != nil {
			return nil, err
		}
	}
	return args, nil
}

// parseArgs parses a comma-separated value list, stopping at (but not
// consuming) the closing ')'.
func (p *parser) parseArgs() ([]ValueId, error) {
	var args []ValueId
	for {
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			return args, nil
		}
		v, err := p.parseValueRef()
		if err != nil {
			return nil, err
		}
		args = append(args, v)
		if p.peek().kind == tokPunct && p.peek().text == "," {
			p.next()
			continue
		}
		if p.peek().kind == tokPunct && p.peek().text == ")" {
			return args, nil
		}
		return nil, p.errf(p.peek(), "expected ',' or ')' in argument list")
	}
}

func (p *parser) parseValueRef() (ValueId, error) {
	t := p.next()
	if t.kind != tokPercent {
		return NoValue, p.errf(t, "expected a value reference, got %s", t.describe())
	}
	id, ok := p.values[t.text]
	if !ok {
		return NoValue, p.errf(t, "unknown value %%%s", t.text)
	}
	return id, nil
}

func (p *parser) parsePlace() (Place, error) {
	t := p.next()
	if t.kind != tokIdent {
		return Place{}, p.errf(t, "expected a place, got %s", t.describe())
	}
	switch t.text {
	case "local":
		nameTok, err := p.expectPercent("a local reference")
		if err != nil {
			return Place{}, err
		}
		id, ok := p.locals[nameTok.text]
		if !ok {
			return Place{}, p.errf(nameTok, "unknown local %%%s", nameTok.text)
		}
		return Place{Kind: PlaceLocal, Local: id}, nil
	case "field":
		if err := p.expectPunct("("); err != nil {
			return Place{}, err
		}
		base, err := p.parsePlace()
		if err != nil {
			return Place{}, err
		}
		if err := p.expectComma(); err != nil {
			return Place{}, err
		}
		nameTok, err := p.expectIdent("a field name")
		if err != nil {
			return Place{}, err
		}
		if err := p.expectPunct(")"); err != nil {
			return Place{}, err
		}
		return Place{Kind: PlaceField, Base: &base, Field: nameTok.text}, nil
	case "deref":
		v, err := p.parseValueRef()
		if err != nil {
			return Place{}, err
		}
		return Place{Kind: PlaceDeref, Deref: v}, nil
	}
	return Place{}, p.errf(t, "expected a place, got %q", t.text)
}

// --- terminators ---

func (p *parser) parseTerminator() error {
	b := p.curBlock
	if b == nil {
		return p.errf(p.peek(), "terminator outside a block")
	}
	t := p.next() // terminator keyword
	switch t.text {
	case "jump":
		b.Term.Kind = TermJump
		args, err := p.parseBlockRef(&b.Term.Target)
		b.Term.Args = args
		if err != nil {
			return err
		}
	case "branch":
		b.Term.Kind = TermBranch
		cond, err := p.parseValueRef()
		if err != nil {
			return err
		}
		b.Term.Cond = cond
		if err := p.expectComma(); err != nil {
			return err
		}
		args, err := p.parseBlockRef(&b.Term.Then)
		b.Term.ThenArgs = args
		if err != nil {
			return err
		}
		if err := p.expectComma(); err != nil {
			return err
		}
		args, err = p.parseBlockRef(&b.Term.Else)
		b.Term.ElseArgs = args
		if err != nil {
			return err
		}
	case "switch":
		b.Term.Kind = TermSwitch
		v, err := p.parseValueRef()
		if err != nil {
			return err
		}
		b.Term.Value = v
		if err := p.expectPunct("{"); err != nil {
			return err
		}
		for {
			if p.peek().kind == tokPunct && p.peek().text == "}" {
				p.next()
				break
			}
			caseTok, err := p.expectIdent("a variant name or 'default'")
			if err != nil {
				return err
			}
			if !caseTok.bol {
				return p.errf(caseTok, "switch case must start on a new line")
			}
			c := SwitchCase{Binding: NoValue}
			if caseTok.text == "default" {
				c.Variant = ""
			} else {
				c.Variant = caseTok.text
				if p.peek().kind == tokPunct && p.peek().text == "(" {
					p.next()
					bindingTok, err := p.expectPercent("a payload binding name")
					if err != nil {
						return err
					}
					if _, dup := p.values[bindingTok.text]; dup {
						return p.errf(bindingTok, "duplicate value %%%s", bindingTok.text)
					}
					payloadType := NoType
					if ot, ok := p.fn.ValueType(b.Term.Value); ok {
						if idx, ok := p.m.VariantIndex(ot, c.Variant); ok {
							if pt, ok := p.m.VariantPayload(ot, idx); ok {
								payloadType = pt
							}
						}
					}
					vid := p.fn.AddValue(bindingTok.text, payloadType, ValueDef{
						Kind:  ValueDefSwitchCase,
						Block: p.blockID(b),
						Case:  len(b.Term.Cases),
					})
					p.values[bindingTok.text] = vid
					c.Binding = vid
					if err := p.expectPunct(")"); err != nil {
						return err
					}
				}
			}
			if err := p.expectPunct("->"); err != nil {
				return err
			}
			args, err := p.parseBlockRef(&c.Target)
			c.Args = args
			if err != nil {
				return err
			}
			b.Term.Cases = append(b.Term.Cases, c)
		}
	case "return":
		b.Term.Kind = TermReturn
		b.Term.Result = NoValue
		if p.peek().kind == tokPercent && !p.peek().bol {
			v, err := p.parseValueRef()
			if err != nil {
				return err
			}
			b.Term.Result = v
		}
	case "fail":
		b.Term.Kind = TermFail
		v, err := p.parseValueRef()
		if err != nil {
			return err
		}
		b.Term.Result = v
	case "panic":
		if p.m.FormatVersion < PanicFormatVersion {
			return p.errf(t, "panic requires MIR format version 2")
		}
		b.Term.Kind = TermPanic
		b.Term.Result = NoValue
	case "unreachable":
		b.Term.Kind = TermUnreachable
	}
	p.curBlock = nil
	return nil
}

// --- types ---

func (p *parser) parseType() (TypeId, error) {
	t := p.next()
	switch {
	case t.kind == tokAtName:
		id, ok := p.m.NamedType(t.text)
		if !ok || (p.inBody && int(id) >= p.typeLimit) {
			return NoType, p.errf(t, "unknown type @%s", t.text)
		}
		return id, nil
	case t.kind == tokIdent:
		switch t.text {
		case "unit":
			return TypeUnit, nil
		case "bool":
			return TypeBool, nil
		case "i8":
			return TypeI8, nil
		case "i16":
			return TypeI16, nil
		case "i32":
			return TypeI32, nil
		case "i64":
			return TypeI64, nil
		case "u8":
			return TypeU8, nil
		case "u16":
			return TypeU16, nil
		case "u32":
			return TypeU32, nil
		case "u64":
			return TypeU64, nil
		case "f32":
			return TypeF32, nil
		case "f64":
			return TypeF64, nil
		case "string":
			return p.m.String(), nil
		case "bytes":
			return p.m.Bytes(), nil
		case "domain_handle":
			return p.m.DomainHandle(), nil
		case "domain_mark":
			return p.m.DomainMark(), nil
		case "cleanup_scope":
			return p.m.CleanupScope(), nil
		case "cleanup_id":
			return p.m.CleanupID(), nil
		case "c_string":
			if p.m.FormatVersion < BindingFormatVersion {
				return NoType, p.errf(t, "c_string requires MIR format version %d", BindingFormatVersion)
			}
			return p.m.CString(), nil
		case "option", "result", "slice", "vec", "array", "safe_ref", "safe_mut", "raw_ptr",
			"table", "id", "table_view", "table_mut_view":
			if t.text == "vec" && p.m.FormatVersion < VecFormatVersion {
				return NoType, p.errf(t, "vec requires MIR format version 4")
			}
			return p.parseStructuralType(t)
		case "function":
			if err := p.expectPunct("("); err != nil {
				return NoType, err
			}
			sig, err := p.parseFuncSig()
			if err != nil {
				return NoType, err
			}
			if err := p.expectPunct(")"); err != nil {
				return NoType, err
			}
			return p.m.FunctionType(sig), nil
		default:
			if id, ok := cScalarID(t.text); ok {
				if p.m.FormatVersion < BindingFormatVersion {
					return NoType, p.errf(t, "%s requires MIR format version 6", t.text)
				}
				return p.m.CRaw(uint64(id)), nil
			}
			if t.text == "c_ptr" || t.text == "c_const_ptr" {
				if p.m.FormatVersion < BindingFormatVersion {
					return NoType, p.errf(t, "%s requires MIR format version 6", t.text)
				}
				if err := p.expectPunct("("); err != nil {
					return NoType, err
				}
				elem, err := p.parseType()
				if err != nil {
					return NoType, err
				}
				if err := p.expectPunct(")"); err != nil {
					return NoType, err
				}
				if t.text == "c_ptr" {
					return p.m.CPtr(elem), nil
				}
				return p.m.CConstPtr(elem), nil
			}
		}
	}
	return NoType, p.errf(t, "expected a type, got %s", t.describe())
}

// cScalarID maps a textual raw C scalar name to its CScalar id.
func cScalarID(name string) (int, bool) {
	for id := 0; id < NumCScalars; id++ {
		if cScalarNames[id] == name {
			return id, true
		}
	}
	return 0, false
}

func (p *parser) constVisible(decl *ConstDecl) bool {
	for i := 0; i < p.constLimit; i++ {
		if &p.m.Constants[i] == decl {
			return true
		}
	}
	return false
}

func (p *parser) parseStructuralType(nameTok *token) (TypeId, error) {
	if err := p.expectPunct("("); err != nil {
		return NoType, err
	}
	first, err := p.parseType()
	if err != nil {
		return NoType, err
	}
	if nameTok.text == "result" {
		if err := p.expectComma(); err != nil {
			return NoType, err
		}
		second, err := p.parseType()
		if err != nil {
			return NoType, err
		}
		if err := p.expectPunct(")"); err != nil {
			return NoType, err
		}
		return p.m.Result(first, second), nil
	}
	if nameTok.text == "array" {
		if err := p.expectComma(); err != nil {
			return NoType, err
		}
		lengthTok := p.next()
		if lengthTok.kind != tokInt {
			return NoType, p.errf(lengthTok, "expected an array length, got %s", lengthTok.describe())
		}
		length, err := strconv.ParseUint(lengthTok.text, 10, 64)
		if err != nil {
			return NoType, p.errf(lengthTok, "array length %q out of range", lengthTok.text)
		}
		if err := p.expectPunct(")"); err != nil {
			return NoType, err
		}
		return p.m.Array(first, length), nil
	}
	if err := p.expectPunct(")"); err != nil {
		return NoType, err
	}
	switch nameTok.text {
	case "option":
		return p.m.Option(first), nil
	case "slice":
		return p.m.Slice(first), nil
	case "vec":
		return p.m.Vec(first), nil
	case "safe_ref":
		return p.m.SafeRef(first), nil
	case "safe_mut":
		return p.m.SafeMut(first), nil
	case "raw_ptr":
		return p.m.RawPtr(first), nil
	case "table":
		return p.m.Table(first), nil
	case "id":
		return p.m.ID(first), nil
	case "table_view":
		return p.m.TableView(first), nil
	case "table_mut_view":
		return p.m.TableMutView(first), nil
	}
	return NoType, p.errf(nameTok, "unknown structural type %q", nameTok.text)
}

// cmpOpByName maps comparison names to operations.
var cmpOpByName = map[string]OpKind{
	"int.eq": OpIntEq, "int.ne": OpIntNe, "int.lt": OpIntLt, "int.le": OpIntLe,
	"int.gt": OpIntGt, "int.ge": OpIntGe,
	"float.eq": OpFloatEq, "float.ne": OpFloatNe, "float.lt": OpFloatLt,
	"float.le": OpFloatLe, "float.gt": OpFloatGt, "float.ge": OpFloatGe,
}

// convOpByName maps conversion names to operations.
var convOpByName = map[string]OpKind{
	"int.trunc": OpIntTrunc, "int.zext": OpIntZext, "int.sext": OpIntSext,
	"int.convert.checked": OpIntConvertChecked, "int.convert.wrap": OpIntConvertWrap,
	"float.convert": OpFloatConvert, "int.from_float": OpIntFromFloat,
	"float.from_int": OpFloatFromInt,
}

// cNumOpByName maps the C-boundary conversion names to operations.
var cNumOpByName = map[string]OpKind{
	"c.num.try": OpCNumTry, "c.num.wrap": OpCNumWrap, "c.num.cast": OpCNumCast,
}

// floatArithOpByName maps the plain IEEE-754 arithmetic names to operations.
var floatArithOpByName = map[string]OpKind{
	"float.add": OpFloatAdd, "float.sub": OpFloatSub,
	"float.mul": OpFloatMul, "float.div": OpFloatDiv,
}

// bitwiseOpByName maps the total bitwise binary names to operations.
var bitwiseOpByName = map[string]OpKind{
	"int.and": OpIntAnd, "int.or": OpIntOr, "int.xor": OpIntXor,
}
