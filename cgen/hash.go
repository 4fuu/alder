package cgen

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
)

// emitHashValue initializes one SipHash-1-3 state from the two key words and
// recursively writes the canonical structural encoding of the value.
func (g *gen) emitHashValue(b *strings.Builder, in *mir.Instr) {
	state := "alder_h" + strconv.Itoa(int(in.Result))
	fmt.Fprintf(b, "  AlderHashState %s; alder_hash_init(&%s, %s, %s);\n", state, state, g.valueExpr(in.A), g.valueExpr(in.B))
	g.emitHashType(b, state, "("+g.valueExpr(in.HashVal)+")", in.TypeOp, 0)
	fmt.Fprintf(b, "  %s = alder_hash_finish(&%s);\n", g.val(in.Result), state)
}

func (g *gen) emitHashType(b *strings.Builder, state, expr string, t mir.TypeId, depth int) {
	if depth > 64 {
		panic("cgen: recursive hash type")
	}
	rec := g.m.Types[t]
	switch rec.Kind {
	case mir.TypePrimitive:
		switch t {
		case mir.TypeBool:
			fmt.Fprintf(b, "  alder_hash_write_uint(&%s, (uint64_t)(%s != 0), UINT64_C(1));\n", state, expr)
		case mir.TypeI8, mir.TypeU8:
			g.emitHashUint(b, state, expr, 1)
		case mir.TypeI16, mir.TypeU16:
			g.emitHashUint(b, state, expr, 2)
		case mir.TypeI32, mir.TypeU32:
			g.emitHashUint(b, state, expr, 4)
		case mir.TypeI64, mir.TypeU64:
			g.emitHashUint(b, state, expr, 8)
		case mir.TypeUnit:
			return
		default:
			panic("cgen: unsupported hash primitive")
		}
	case mir.TypeString, mir.TypeBytes:
		fmt.Fprintf(b, "  alder_hash_write_u64(&%s, (uint64_t)%s.len);\n", state, expr)
		fmt.Fprintf(b, "  alder_hash_write_bytes(&%s, (const uint8_t *)%s.data, (uint64_t)%s.len);\n", state, expr, expr)
	case mir.TypeOption:
		fmt.Fprintf(b, "  alder_hash_write_uint(&%s, (uint64_t)%s.alder_tag, UINT64_C(1));\n", state, expr)
		if rec.Elem != mir.TypeUnit {
			fmt.Fprintf(b, "  if (%s.alder_tag == 1U) {\n", expr)
			g.emitHashType(b, state, expr+".alder_u.alder_p1", rec.Elem, depth+1)
			b.WriteString("  }\n")
		}
	case mir.TypeResult:
		fmt.Fprintf(b, "  alder_hash_write_uint(&%s, (uint64_t)%s.alder_tag, UINT64_C(1));\n", state, expr)
		fmt.Fprintf(b, "  if (%s.alder_tag == 0U) {\n", expr)
		if rec.OK != mir.TypeUnit {
			g.emitHashType(b, state, expr+".alder_u.alder_p0", rec.OK, depth+1)
		}
		b.WriteString("  } else {\n")
		if rec.Err != mir.TypeUnit {
			g.emitHashType(b, state, expr+".alder_u.alder_p1", rec.Err, depth+1)
		}
		b.WriteString("  }\n")
	case mir.TypeAggregate:
		for at, field := range rec.Fields {
			if field.Type == mir.TypeUnit {
				continue
			}
			g.emitHashType(b, state, fmt.Sprintf("%s.alder_f%d", expr, at), field.Type, depth+1)
		}
	case mir.TypeEnum:
		fmt.Fprintf(b, "  alder_hash_write_u64(&%s, (uint64_t)%s.alder_tag);\n", state, expr)
		fmt.Fprintf(b, "  switch (%s.alder_tag) {\n", expr)
		for at, variant := range rec.Variants {
			fmt.Fprintf(b, "  case %dU:\n", at)
			if variant.Payload != mir.TypeUnit {
				g.emitHashType(b, state, fmt.Sprintf("%s.alder_u.alder_p%d", expr, at), variant.Payload, depth+1)
			}
			b.WriteString("    break;\n")
		}
		b.WriteString("  default:\n    alder_runtime_panic(\"unreachable\");\n  }\n")
	default:
		panic("cgen: unsupported structural hash type")
	}
}

func (g *gen) emitHashUint(b *strings.Builder, state, expr string, width int) {
	fmt.Fprintf(b, "  alder_hash_write_uint(&%s, (uint64_t)%s, UINT64_C(%d));\n", state, expr, width)
}
