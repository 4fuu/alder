// Package mir defines the typed, source-independent Aster MIR contract:
// the in-memory representation, the deterministic textual printer and parser,
// and the shared type inference used by both the parser and the verifier.
//
// MIR modules use stable numeric IDs and contiguous slices instead of
// pointer-linked compiler graphs. Printed and parsed output never depends on
// host map iteration order, memory addresses, or temporary paths.
package mir

// TypeId identifies a type in a Module type table. The first
// NumPrimitiveTypes slots are the canonical primitive types; later slots hold
// named aggregate and enum declarations and interned structural types.
type TypeId uint32

// FunctionId identifies a function in Module.Functions (declaration order).
type FunctionId uint32

// ImportId identifies an imported C declaration in Module.Imports.
type ImportId uint32

// BlockId identifies a block within a function (declaration order).
type BlockId uint32

// ValueId identifies an SSA-like temporary value within a function.
type ValueId uint32

// LocalId identifies a mutable local slot within a function.
type LocalId uint32

// DomainId is reserved for static domain identity in later MIR versions.
type DomainId uint32

// CleanupId is reserved for static cleanup identity in later MIR versions.
type CleanupId uint32

// SpanId is reserved for source-span diagnostics once the frontend exists.
type SpanId uint32

// Sentinel identities for "no such object" operand positions.
const (
	NoType     = TypeId(^uint32(0))
	NoFunction = FunctionId(^uint32(0))
	NoImport   = ImportId(^uint32(0))
	NoBlock    = BlockId(^uint32(0))
	NoValue    = ValueId(^uint32(0))
	NoLocal    = LocalId(^uint32(0))
)
