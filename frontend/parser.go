package frontend

import (
	"fmt"
	"strconv"
)

// parser is a recursive-descent parser over the token stream.
type parser struct {
	toks      []token
	i         int
	exprDepth int
}

func tokenPos(t token) pos {
	return pos{line: t.line, col: t.col, span: t.span}
}

// parseModule parses a complete source module.
func parseModule(src string) ([]Decl, error) {
	return parseModuleSource(Source{Text: src})
}

func parseModuleSource(source Source) ([]Decl, error) {
	toks, err := lexSource(source)
	if err != nil {
		return nil, err
	}
	p := &parser{toks: toks}
	var decls []Decl
	for p.cur().kind != tokEOF {
		d, err := p.parseDecl()
		if err != nil {
			return nil, err
		}
		decls = append(decls, d)
		if p.cur().kind != tokEOF && !p.lineBreakBeforeCurrent() {
			return nil, p.errf(p.cur(), "declarations must be separated by a physical line break")
		}
	}
	return decls, nil
}

func (p *parser) cur() token { return p.toks[p.i] }
func (p *parser) peek() token {
	if p.i+1 < len(p.toks) {
		return p.toks[p.i+1]
	}
	return p.toks[len(p.toks)-1]
}
func (p *parser) advance() token {
	t := p.toks[p.i]
	if p.i < len(p.toks)-1 {
		p.i++
	}
	return t
}

func (p *parser) errf(t token, format string, args ...any) error {
	return &astError{line: t.line, col: t.col, msg: fmt.Sprintf(format, args...), code: CodeSyntax, span: t.span}
}

func (p *parser) expectPunct(text string) error {
	t := p.cur()
	if t.kind != tokPunct || t.text != text {
		return p.errf(t, "expected %q, got %s", text, t.describe())
	}
	p.advance()
	return nil
}

func (p *parser) trailingClose(close string) bool {
	return p.cur().kind == tokPunct && p.cur().text == close
}

func (p *parser) lineBreakBeforeCurrent() bool {
	return p.i > 0 && p.cur().line > p.toks[p.i-1].line
}

func (p *parser) requireSameLineAfterPrevious(what string) error {
	if p.lineBreakBeforeCurrent() && p.exprDepth == 0 {
		return p.errf(p.cur(), "%s may continue across a line break only inside delimiters", what)
	}
	return nil
}

func (p *parser) expectKeyword(kw keyword, what string) error {
	t := p.cur()
	if t.kind != tokIdent || t.kw != kw {
		return p.errf(t, "expected %s, got %s", what, t.describe())
	}
	p.advance()
	return nil
}

func (p *parser) expectIdent(what string) (token, error) {
	t := p.cur()
	if t.kind != tokIdent || t.kw != kwNone {
		return token{}, p.errf(t, "expected %s, got %s", what, t.describe())
	}
	p.advance()
	return t, nil
}

func (p *parser) parseDecl() (Decl, error) {
	t := p.cur()
	switch {
	case t.kind == tokIdent && t.kw == kwImport:
		return p.parseImport()
	case t.kind == tokIdent && t.kw == kwType:
		return p.parseTypeDecl(false)
	case t.kind == tokIdent && t.kw == kwEnum:
		return p.parseTypeDecl(true)
	case t.kind == tokIdent && t.kw == kwFn:
		return p.parseFnDecl()
	}
	return nil, p.errf(t, "expected a declaration (import c, type, enum, or fn), got %s", t.describe())
}

func (p *parser) parseImport() (Decl, error) {
	start := p.advance() // import
	cur := p.cur()
	if cur.kind != tokIdent || cur.text != "c" {
		return nil, p.errf(cur, "expected \"c\" after import, got %s", cur.describe())
	}
	p.advance()
	name, err := p.expectIdent("an import name")
	if err != nil {
		return nil, err
	}
	if err := p.expectPunct(":"); err != nil {
		return nil, err
	}
	sig, err := p.parseFnSig()
	if err != nil {
		return nil, err
	}
	return &ImportDecl{P: tokenPos(start), Name: name.text, Sig: sig}, nil
}

func (p *parser) parseFnSig() (FuncSigExpr, error) {
	if err := p.expectKeyword(kwFn, "\"fn\""); err != nil {
		return FuncSigExpr{}, err
	}
	if err := p.expectPunct("("); err != nil {
		return FuncSigExpr{}, err
	}
	var params []TypeExpr
	if p.cur().kind == tokPunct && p.cur().text == ")" {
		p.advance()
	} else {
		for {
			ty, err := p.parseType()
			if err != nil {
				return FuncSigExpr{}, err
			}
			params = append(params, ty)
			if p.cur().kind == tokPunct && p.cur().text == "," {
				p.advance()
				if p.trailingClose(")") {
					break
				}
				continue
			}
			break
		}
		if err := p.expectPunct(")"); err != nil {
			return FuncSigExpr{}, err
		}
	}
	if err := p.expectPunct("->"); err != nil {
		return FuncSigExpr{}, err
	}
	result, err := p.parseType()
	if err != nil {
		return FuncSigExpr{}, err
	}
	return FuncSigExpr{Params: params, Result: result}, nil
}

func (p *parser) parseTypeDecl(isEnum bool) (Decl, error) {
	start := p.advance() // type / enum
	name, err := p.expectIdent("a type name")
	if err != nil {
		return nil, err
	}
	d := &TypeDecl{P: tokenPos(start), Name: name.text, IsEnum: isEnum}
	if p.cur().kind == tokPunct && p.cur().text == "(" {
		// Type parameters: Name(A: type, B: type)
		p.advance()
		for {
			pn, err := p.expectIdent("a type parameter name")
			if err != nil {
				return nil, err
			}
			if err := p.expectPunct(":"); err != nil {
				return nil, err
			}
			if p.cur().kw == kwType || p.cur().kind == tokIdent && p.cur().text == "type" {
				p.advance()
			} else {
				return nil, p.errf(p.cur(), "expected the keyword \"type\"")
			}
			d.Params = append(d.Params, pn.text)
			if p.cur().kind == tokPunct && p.cur().text == "," {
				p.advance()
				if p.trailingClose(")") {
					break
				}
				continue
			}
			break
		}
		if err := p.expectPunct(")"); err != nil {
			return nil, err
		}
	}
	if err := p.expectPunct("{"); err != nil {
		return nil, err
	}
	if isEnum {
		for p.cur().kind == tokIdent && p.cur().kw == kwNone {
			vn := p.advance()
			v := VariantDecl{Name: vn.text}
			if p.cur().kind == tokPunct && p.cur().text == "(" {
				p.advance()
				label, err := p.expectIdent("a payload label")
				if err != nil {
					return nil, err
				}
				if err := p.expectPunct(":"); err != nil {
					return nil, p.errf(p.cur(), "enum payload requires a label before its type")
				}
				payload, err := p.parseType()
				if err != nil {
					return nil, err
				}
				v.PayloadLabel, v.Payload = label.text, payload
				if err := p.expectPunct(")"); err != nil {
					return nil, err
				}
			}
			d.Variants = append(d.Variants, v)
			if p.cur().kind == tokPunct && (p.cur().text == "," || p.cur().text == ";") {
				return nil, p.errf(p.cur(), "enum variants are separated by line breaks, not %q", p.cur().text)
			}
			if !p.trailingClose("}") && !p.lineBreakBeforeCurrent() {
				return nil, p.errf(p.cur(), "enum variants must be separated by a line break")
			}
		}
	} else {
		for p.cur().kind == tokIdent && p.cur().kw == kwNone {
			fn, err := p.expectIdent("a field name")
			if err != nil {
				return nil, err
			}
			if err := p.expectPunct(":"); err != nil {
				return nil, err
			}
			ft, err := p.parseType()
			if err != nil {
				return nil, err
			}
			d.Fields = append(d.Fields, FieldDecl{Name: fn.text, Type: ft})
			if p.cur().kind == tokPunct && (p.cur().text == "," || p.cur().text == ";") {
				return nil, p.errf(p.cur(), "type fields are separated by line breaks, not %q", p.cur().text)
			}
			if !p.trailingClose("}") && !p.lineBreakBeforeCurrent() {
				return nil, p.errf(p.cur(), "type fields must be separated by a line break")
			}
		}
	}
	if err := p.expectPunct("}"); err != nil {
		return nil, err
	}
	return d, nil
}

func (p *parser) parseFnDecl() (Decl, error) {
	start := p.advance() // fn
	name, err := p.expectIdent("a function name")
	if err != nil {
		return nil, err
	}
	if err := p.expectPunct("("); err != nil {
		return nil, err
	}
	d := &FnDecl{P: tokenPos(start), Name: name.text}
	if p.cur().kind == tokPunct && p.cur().text == ")" {
		p.advance()
	} else {
		seenRuntimeParam := false
		for {
			pn, err := p.expectIdent("a parameter name")
			if err != nil {
				return nil, err
			}
			if err := p.expectPunct(":"); err != nil {
				return nil, err
			}
			if p.cur().kw == kwType {
				if seenRuntimeParam {
					return nil, p.errf(pn, "compile-time type parameters must precede runtime parameters")
				}
				p.advance()
				d.Params = append(d.Params, ParamDecl{Name: pn.text, Kind: paramType})
			} else {
				pt, err := p.parseType()
				if err != nil {
					return nil, err
				}
				d.Params = append(d.Params, ParamDecl{Name: pn.text, Kind: paramRuntime, Type: pt})
				seenRuntimeParam = true
			}
			if p.cur().kind == tokPunct && p.cur().text == "," {
				p.advance()
				if p.trailingClose(")") {
					break
				}
				continue
			}
			break
		}
		if err := p.expectPunct(")"); err != nil {
			return nil, err
		}
	}
	if err := p.expectPunct("->"); err != nil {
		return nil, err
	}
	result, err := p.parseType()
	if err != nil {
		return nil, err
	}
	d.Result = result
	body, err := p.parseBlock()
	if err != nil {
		return nil, err
	}
	d.Body = body
	return d, nil
}

func (p *parser) parseBlock() (*Block, error) {
	start := p.cur()
	if err := p.expectPunct("{"); err != nil {
		return nil, err
	}
	b := &Block{P: tokenPos(start)}
	for !(p.cur().kind == tokPunct && p.cur().text == "}") {
		if p.cur().kind == tokEOF {
			return nil, p.errf(p.cur(), "expected \"}\", got end of input")
		}
		s, err := p.parseStmt()
		if err != nil {
			return nil, err
		}
		b.Stmts = append(b.Stmts, s)
		if !p.trailingClose("}") && !p.lineBreakBeforeCurrent() {
			return nil, p.errf(p.cur(), "statements must be separated by a physical line break")
		}
	}
	p.advance() // }
	return b, nil
}

func (p *parser) parseStmt() (Stmt, error) {
	t := p.cur()
	if t.kind == tokIdent {
		switch t.kw {
		case kwLet, kwVar:
			return p.parseLet()
		case kwIf:
			return p.parseIf()
		case kwWhile:
			return p.parseWhile()
		case kwFor:
			return p.parseFor()
		case kwReturn:
			return p.parseReturn()
		case kwUsing:
			return p.parseUsing()
		case kwMatch:
			x, err := p.parseMatch()
			if err != nil {
				return nil, err
			}
			return &ExprStmt{P: tokenPos(t), X: x}, nil
		}
	}
	if t.kind == tokPunct && t.text == "{" {
		return p.parseBlock()
	}
	// Assignment or expression statement.
	x, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	if p.cur().kind == tokPunct && p.cur().text == "=" {
		target, err := p.assignmentTarget(x, t)
		if err != nil {
			return nil, err
		}
		p.advance()
		if err := p.requireSameLineAfterPrevious("an assignment"); err != nil {
			return nil, err
		}
		value, err := p.parseExpr()
		if err != nil {
			return nil, err
		}
		return &Assign{P: tokenPos(t), Target: target, Value: value}, nil
	}
	return &ExprStmt{P: tokenPos(t), X: x}, nil
}

// assignmentTarget converts a parsed expression into an assignment target.
func (p *parser) assignmentTarget(x Expr, start token) (AssignTarget, error) {
	if f, ok := x.(*Field); ok {
		if idx, ok := f.Base.(*Index); ok {
			id, ok := idx.Base.(*Ident)
			if !ok {
				return AssignTarget{}, p.errf(start, "assignment target must be a variable, variable field, or variable index")
			}
			return AssignTarget{P: tokenPos(start), Name: id.Name, Index: idx.Index, Field: f.Name}, nil
		}
		id, ok := f.Base.(*Ident)
		if !ok {
			return AssignTarget{}, p.errf(start, "assignment target must be a variable, variable field, or variable index")
		}
		return AssignTarget{P: tokenPos(start), Name: id.Name, Field: f.Name}, nil
	}
	if e, ok := x.(*Index); ok {
		id, ok := e.Base.(*Ident)
		if !ok {
			return AssignTarget{}, p.errf(start, "assignment target must be a variable, variable field, or variable index")
		}
		return AssignTarget{P: tokenPos(start), Name: id.Name, Index: e.Index}, nil
	}
	if e, ok := x.(*Ident); ok {
		return AssignTarget{P: tokenPos(start), Name: e.Name}, nil
	}
	return AssignTarget{}, p.errf(start, "assignment target must be a variable, variable field, or variable index")
}

func (p *parser) parseLet() (Stmt, error) {
	t := p.advance() // let / var
	name, err := p.expectIdent("a binding name")
	if err != nil {
		return nil, err
	}
	s := &Let{P: tokenPos(t), Var: t.kw == kwVar, Name: name.text}
	if p.cur().kind == tokPunct && p.cur().text == ":" {
		p.advance()
		ty, err := p.parseType()
		if err != nil {
			return nil, err
		}
		s.Type = ty
	}
	if err := p.expectPunct("="); err != nil {
		return nil, err
	}
	if err := p.requireSameLineAfterPrevious("an initializer"); err != nil {
		return nil, err
	}
	value, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	s.Value = value
	return s, nil
}

func (p *parser) parseIf() (Stmt, error) {
	t := p.advance() // if
	if err := p.requireSameLineAfterPrevious("an if condition"); err != nil {
		return nil, err
	}
	cond, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	then, err := p.parseBlock()
	if err != nil {
		return nil, err
	}
	s := &IfStmt{P: tokenPos(t), Cond: cond, Then: then}
	if p.cur().kind == tokIdent && p.cur().kw == kwElse {
		p.advance()
		if p.cur().kind == tokIdent && p.cur().kw == kwIf {
			// `else if` is an else whose block holds one nested if statement.
			nested, err := p.parseIf()
			if err != nil {
				return nil, err
			}
			s.Else = &Block{P: nested.stmtPos(), Stmts: []Stmt{nested}}
			return s, nil
		}
		elseB, err := p.parseBlock()
		if err != nil {
			return nil, err
		}
		s.Else = elseB
	}
	return s, nil
}

func (p *parser) parseWhile() (Stmt, error) {
	t := p.advance() // while
	if err := p.requireSameLineAfterPrevious("a while condition"); err != nil {
		return nil, err
	}
	cond, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	body, err := p.parseBlock()
	if err != nil {
		return nil, err
	}
	return &WhileStmt{P: tokenPos(t), Cond: cond, Body: body}, nil
}

func (p *parser) parseFor() (Stmt, error) {
	t := p.advance() // for
	name, err := p.expectIdent("a binding name")
	if err != nil {
		return nil, err
	}
	if err := p.expectKeyword(kwIn, "\"in\""); err != nil {
		return nil, err
	}
	if err := p.requireSameLineAfterPrevious("a for expression"); err != nil {
		return nil, err
	}
	seq, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	body, err := p.parseBlock()
	if err != nil {
		return nil, err
	}
	return &ForStmt{P: tokenPos(t), Name: name.text, Seq: seq, Body: body}, nil
}

func (p *parser) parseUsing() (Stmt, error) {
	t := p.advance() // using
	name, err := p.expectIdent("a binding name")
	if err != nil {
		return nil, err
	}
	if err := p.expectPunct("="); err != nil {
		return nil, err
	}
	if err := p.requireSameLineAfterPrevious("a using initializer"); err != nil {
		return nil, err
	}
	value, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	if err := p.expectKeyword(kwWith, "\"with\""); err != nil {
		return nil, err
	}
	if err := p.requireSameLineAfterPrevious("a using statement"); err != nil {
		return nil, err
	}
	cleanup, err := p.expectIdent("a cleanup function name")
	if err != nil {
		return nil, err
	}
	return &UsingStmt{P: tokenPos(t), Name: name.text, Value: value, Cleanup: cleanup.text}, nil
}

func (p *parser) parseReturn() (Stmt, error) {
	t := p.advance() // return
	s := &ReturnStmt{P: tokenPos(t)}
	if p.trailingClose("}") || p.cur().line > t.line {
		return s, nil
	}
	x, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	s.Value = x
	return s, nil
}

func (p *parser) parseType() (TypeExpr, error) {
	t := p.cur()
	if t.kind == tokPunct && t.text == "[" {
		p.advance()
		elem, err := p.parseType()
		if err != nil {
			return nil, err
		}
		if err := p.expectPunct("]"); err != nil {
			return nil, err
		}
		return &SliceType{P: tokenPos(t), Elem: elem}, nil
	}
	if t.kind != tokIdent || t.kw != kwNone {
		if t.kind == tokInt {
			p.advance()
			return &PrimType{P: tokenPos(t), Name: t.text}, nil
		}
		return nil, p.errf(t, "expected a type, got %s", t.describe())
	}
	name := p.advance()
	if p.cur().kind == tokPunct && p.cur().text == "(" {
		p.advance()
		var args []TypeExpr
		if p.cur().kind == tokPunct && p.cur().text == ")" {
			p.advance()
		} else {
			for {
				arg, err := p.parseType()
				if err != nil {
					return nil, err
				}
				args = append(args, arg)
				if p.cur().kind == tokPunct && p.cur().text == "," {
					p.advance()
					if p.trailingClose(")") {
						break
					}
					continue
				}
				break
			}
			if err := p.expectPunct(")"); err != nil {
				return nil, err
			}
		}
		return &AppType{P: tokenPos(t), Name: name.text, Args: args}, nil
	}
	return &PrimType{P: tokenPos(t), Name: name.text}, nil
}

// parseExpr parses an expression with the precedence table:
// || < && < == != < < <= > >= < | < ^ < & < << >> < + - < * / % < unary < postfix.
func (p *parser) parseExpr() (Expr, error) {
	return p.parseBinary(0)
}

var binaryPrecedence = map[string]int{
	"||": 1,
	"&&": 2,
	"==": 3, "!=": 3,
	"<": 4, "<=": 4, ">": 4, ">=": 4,
	"|":  5,
	"^":  6,
	"&":  7,
	"<<": 8, ">>": 8,
	"+": 9, "-": 9,
	"*": 10, "/": 10, "%": 10,
}

func (p *parser) parseBinary(minPrec int) (Expr, error) {
	left, err := p.parseUnary()
	if err != nil {
		return nil, err
	}
	for {
		t := p.cur()
		if t.kind != tokPunct {
			return left, nil
		}
		prec, ok := binaryPrecedence[t.text]
		if !ok || prec < minPrec {
			return left, nil
		}
		if err := p.requireSameLineAfterPrevious("an expression"); err != nil {
			return nil, err
		}
		op := p.advance()
		if err := p.requireSameLineAfterPrevious("an expression"); err != nil {
			return nil, err
		}
		right, err := p.parseBinary(prec + 1)
		if err != nil {
			return nil, err
		}
		left = &Binary{P: tokenPos(t), Op: op.text, X: left, Y: right}
	}
}

func (p *parser) parseUnary() (Expr, error) {
	t := p.cur()
	if t.kind == tokPunct && (t.text == "-" || t.text == "!" || t.text == "~") {
		p.advance()
		if err := p.requireSameLineAfterPrevious("a unary expression"); err != nil {
			return nil, err
		}
		x, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		return &Unary{P: tokenPos(t), Op: t.text, X: x}, nil
	}
	return p.parsePostfix()
}

func (p *parser) parsePostfix() (Expr, error) {
	x, err := p.parsePrimary()
	if err != nil {
		return nil, err
	}
	for {
		t := p.cur()
		if t.kind == tokPunct && t.text == "(" {
			if err := p.requireSameLineAfterPrevious("a call"); err != nil {
				return nil, err
			}
			p.advance()
			p.exprDepth++
			var args []Expr
			if p.cur().kind == tokPunct && p.cur().text == ")" {
				p.advance()
				p.exprDepth--
			} else {
				for {
					var arg Expr
					var err error
					if p.cur().kind == tokIdent && p.cur().kw == kwNone && p.peek().text == ":" {
						n := p.advance()
						p.advance()
						v, e := p.parseExpr()
						err = e
						arg = &NamedArg{P: tokenPos(n), Name: n.text, Value: v}
					} else {
						arg, err = p.parseExpr()
					}
					if err != nil {
						return nil, err
					}
					args = append(args, arg)
					if p.cur().kind == tokPunct && p.cur().text == "," {
						p.advance()
						if p.trailingClose(")") {
							break
						}
						continue
					}
					break
				}
				if err := p.expectPunct(")"); err != nil {
					return nil, err
				}
				p.exprDepth--
			}
			x = &Call{P: tokenPos(t), Callee: x, Args: args}
			continue
		}
		if t.kind == tokPunct && t.text == "." {
			if err := p.requireSameLineAfterPrevious("field access"); err != nil {
				return nil, err
			}
			p.advance()
			name, err := p.expectIdent("a field name")
			if err != nil {
				return nil, err
			}
			x = &Field{P: tokenPos(t), Base: x, Name: name.text}
			continue
		}
		if t.kind == tokPunct && t.text == "[" {
			if err := p.requireSameLineAfterPrevious("indexing"); err != nil {
				return nil, err
			}
			p.advance()
			p.exprDepth++
			idx, err := p.parseExpr()
			if err != nil {
				return nil, err
			}
			if err := p.expectPunct("]"); err != nil {
				return nil, err
			}
			p.exprDepth--
			x = &Index{P: tokenPos(t), Base: x, Index: idx}
			continue
		}
		return x, nil
	}
}

func parseInterpLit(t token) (Expr, error) {
	parts := make([]InterpPart, 0, len(t.interp))
	hasExpression := false
	for _, piece := range t.interp {
		if piece.literal != "" {
			parts = append(parts, InterpPart{Literal: piece.literal})
		}
		if piece.tokens == nil {
			continue
		}
		sub := &parser{toks: piece.tokens}
		expr, err := sub.parseExpr()
		if err != nil {
			return nil, err
		}
		if sub.cur().kind != tokEOF {
			return nil, sub.errf(sub.cur(), "unexpected token in interpolation expression")
		}
		parts = append(parts, InterpPart{Expr: expr})
		hasExpression = true
	}
	if !hasExpression {
		return nil, &astError{line: t.line, col: t.col, msg: "interpolation expression is empty", code: CodeSyntax, span: t.span}
	}
	return &InterpLit{P: tokenPos(t), Parts: parts}, nil
}

func (p *parser) parsePrimary() (Expr, error) {
	t := p.cur()
	switch {
	case t.kind == tokPunct && t.text == "[":
		p.advance()
		p.exprDepth++
		var elems []Expr
		if p.cur().text != "]" {
			for {
				e, err := p.parseExpr()
				if err != nil {
					return nil, err
				}
				elems = append(elems, e)
				if p.cur().text != "," {
					break
				}
				p.advance()
				if p.cur().text == "]" {
					break
				}
			}
		}
		if err := p.expectPunct("]"); err != nil {
			return nil, err
		}
		p.exprDepth--
		return &ArrayLit{P: tokenPos(t), Elems: elems}, nil
	case t.kind == tokInt:
		p.advance()
		value, overflow := parseIntLiteral(t.text)
		if overflow {
			return nil, p.errf(t, "integer literal %s is out of range", t.text)
		}
		return &IntLit{P: tokenPos(t), Text: t.text, Value: value}, nil
	case t.kind == tokFloat:
		p.advance()
		v, err := strconv.ParseFloat(t.text, 64)
		if err != nil {
			return nil, p.errf(t, "invalid float literal %s", t.text)
		}
		return &FloatLit{P: tokenPos(t), Value: v}, nil
	case t.kind == tokStr:
		p.advance()
		if len(t.interp) != 0 {
			return parseInterpLit(t)
		}
		return &StrLit{P: tokenPos(t), Value: t.text}, nil
	case t.kind == tokIdent:
		switch t.kw {
		case kwTrue, kwFalse:
			p.advance()
			return &BoolLit{P: tokenPos(t), Value: t.kw == kwTrue}, nil
		case kwTry:
			p.advance()
			if err := p.requireSameLineAfterPrevious("a try expression"); err != nil {
				return nil, err
			}
			x, err := p.parseUnary()
			if err != nil {
				return nil, err
			}
			return &Try{P: tokenPos(t), X: x}, nil
		case kwMatch:
			return p.parseMatch()
		case kwUnsafe:
			return p.parseUnsafeC()
		case kwNone:
			p.advance()
			return &Ident{P: tokenPos(t), Name: t.text}, nil
		}
		return nil, p.errf(t, "expected an expression, got %q", t.text)
	case t.kind == tokPunct && t.text == "(":
		p.advance()
		if p.cur().kind == tokPunct && p.cur().text == ")" {
			p.advance()
			return &UnitLit{P: tokenPos(t)}, nil
		}
		p.exprDepth++
		x, err := p.parseExpr()
		if err != nil {
			return nil, err
		}
		if err := p.expectPunct(")"); err != nil {
			return nil, err
		}
		p.exprDepth--
		return x, nil
	}
	return nil, p.errf(t, "expected an expression, got %s", t.describe())
}

func (p *parser) parseUnsafeC() (Expr, error) {
	t := p.advance()
	c, err := p.expectIdent("\"c\"")
	if err != nil {
		return nil, err
	}
	if c.text != "c" {
		return nil, p.errf(c, "expected \"c\" after unsafe")
	}
	if err := p.expectPunct("{"); err != nil {
		return nil, err
	}
	p.exprDepth++
	x, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	call, ok := x.(*Call)
	if !ok {
		return nil, p.errf(t, "unsafe c block must contain exactly one direct call")
	}
	if err := p.expectPunct("}"); err != nil {
		return nil, p.errf(p.cur(), "unsafe c block must contain exactly one direct call")
	}
	p.exprDepth--
	return &UnsafeC{P: tokenPos(t), Call: call}, nil
}

func (p *parser) parseMatch() (Expr, error) {
	t := p.advance() // match
	if err := p.requireSameLineAfterPrevious("a match expression"); err != nil {
		return nil, err
	}
	value, err := p.parseUnary()
	if err != nil {
		return nil, err
	}
	if err := p.expectPunct("{"); err != nil {
		return nil, err
	}
	p.exprDepth++
	m := &Match{P: tokenPos(t), Value: value}
	for {
		if p.cur().kind == tokPunct && p.cur().text == "}" {
			p.advance()
			p.exprDepth--
			return m, nil
		}
		arm, err := p.parseMatchArm()
		if err != nil {
			return nil, err
		}
		m.Arms = append(m.Arms, arm)
		if p.cur().kind == tokPunct && (p.cur().text == "," || p.cur().text == ";") {
			return nil, p.errf(p.cur(), "match arms are separated by line breaks, not %q", p.cur().text)
		}
		if !p.trailingClose("}") && !p.lineBreakBeforeCurrent() {
			return nil, p.errf(p.cur(), "match arms must be separated by a line break")
		}
	}
}

func (p *parser) parseMatchArm() (MatchArm, error) {
	t := p.cur()
	if t.kind == tokIdent && t.kw == kwNone && t.text == "_" {
		p.advance()
	} else {
		name, err := p.expectIdent("a variant name or \"_\"")
		if err != nil {
			return MatchArm{}, err
		}
		arm := MatchArm{Variant: name.text}
		if p.cur().kind == tokPunct && p.cur().text == "(" {
			p.advance()
			bind, err := p.expectIdent("a binding name")
			if err != nil {
				return MatchArm{}, err
			}
			arm.Bind = bind.text
			if err := p.expectPunct(")"); err != nil {
				return MatchArm{}, err
			}
		}
		if err := p.expectPunct("=>"); err != nil {
			return MatchArm{}, err
		}
		body, err := p.parseExpr()
		if err != nil {
			return MatchArm{}, err
		}
		arm.Body = body
		return arm, nil
	}
	if err := p.expectPunct("=>"); err != nil {
		return MatchArm{}, err
	}
	body, err := p.parseExpr()
	if err != nil {
		return MatchArm{}, err
	}
	return MatchArm{Body: body}, nil
}
