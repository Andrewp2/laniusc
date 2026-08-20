// Shared GPU lowering records and opcodes. Rust constants are generated from
// the declarations marked `IR_OPCODE`; keep numeric ownership in this file.

// IR_OPCODE
static const uint SEMANTIC_LIR_OP_INVALID = 0u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CONST_I32 = 1u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CONST_F32 = 2u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_VALUE_GET = 3u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_VALUE_SET = 4u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_ADD = 5u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_SUB = 6u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_MUL = 7u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_DIV = 8u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_REM = 9u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BIT_AND = 10u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BIT_OR = 11u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BIT_XOR = 12u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_SHIFT_LEFT = 13u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_SHIFT_RIGHT = 14u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_COMPARE = 15u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_NEGATE = 16u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_LOGICAL_NOT = 17u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CONVERT = 18u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CALL = 19u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CALL_HOST = 20u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BLOCK_BEGIN = 21u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_LOOP_BEGIN = 22u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_IF_BEGIN = 23u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_ELSE = 24u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CONTROL_END = 25u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BRANCH = 26u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_BRANCH_IF = 27u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_RETURN = 28u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_DROP = 29u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_ADDRESS = 30u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_LOAD = 31u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_STORE = 32u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_AGGREGATE_COPY = 33u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CONST_STRING = 34u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_LOGICAL_AND = 35u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_LOGICAL_OR = 36u;
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_AGGREGATE_NEW = 37u;
// Compiler-defined operation selected during type checking (for example the
// language's print/assert family). Runtime host services use CALL_HOST and
// remain a distinct ABI boundary.
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CALL_INTRINSIC = 38u;
// A checked call whose definition belongs to another bounded compilation
// unit. Operands a/b/c are the canonical library/unit/declaration identity.
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_CALL_SYMBOL = 39u;
// A scheduled semantic dependency row that intentionally emits no target
// instruction. Recipes use this to preserve uniform parallel row layouts
// when only some pattern forms require an intermediate machine operation.
// IR_OPCODE
static const uint SEMANTIC_LIR_OP_NOP = 40u;

// Canonical scalar type shared by semantic and target lowering. Pointer width
// is selected by the target: 64 bits on x86_64 and 32 bits on Wasm32.
static const uint SEMANTIC_LIR_TY_STRING = 7u;
static const uint SEMANTIC_LIR_TY_POINTER = 8u;

// Runtime services retain the type checker's canonical language-symbol values
// at the semantic-LIR boundary. Naming the complete namespace here makes the
// ABI explicit and keeps target shaders independent of symbol-table trivia.
// IR_OPCODE
static const uint HOST_SERVICE_OPEN_READ_PATH = 20u;
// IR_OPCODE
static const uint HOST_SERVICE_OPEN_WRITE_PATH = 21u;
// IR_OPCODE
static const uint HOST_SERVICE_READ_I32 = 22u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_TEXT = 23u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_I32 = 24u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_BYTE = 25u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_NEWLINE = 26u;
// IR_OPCODE
static const uint HOST_SERVICE_CLOSE_FILE = 27u;
// IR_OPCODE
static const uint HOST_SERVICE_I32_TO_F32 = 28u;
// IR_OPCODE
static const uint HOST_SERVICE_EXIT = 29u;
// IR_OPCODE
static const uint HOST_SERVICE_SECURE_U32 = 30u;
// IR_OPCODE
static const uint HOST_SERVICE_ALLOC = 31u;
// IR_OPCODE
static const uint HOST_SERVICE_DEALLOC = 32u;
// IR_OPCODE
static const uint HOST_SERVICE_ARGC = 33u;
// IR_OPCODE
static const uint HOST_SERVICE_ARG_LEN = 34u;
// IR_OPCODE
static const uint HOST_SERVICE_ARG_READ = 35u;
// IR_OPCODE
static const uint HOST_SERVICE_UNIX_SECONDS = 36u;
// IR_OPCODE
static const uint HOST_SERVICE_CURRENT_DIR_READ = 37u;
// IR_OPCODE
static const uint HOST_SERVICE_VAR_COUNT = 38u;
// IR_OPCODE
static const uint HOST_SERVICE_VAR_KEY_LEN = 39u;
// IR_OPCODE
static const uint HOST_SERVICE_VAR_KEY_READ = 40u;
// IR_OPCODE
static const uint HOST_SERVICE_VAR_LEN = 41u;
// IR_OPCODE
static const uint HOST_SERVICE_VAR_READ = 42u;
// IR_OPCODE
static const uint HOST_SERVICE_CLOSE = 43u;
// IR_OPCODE
static const uint HOST_SERVICE_READ = 44u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE = 45u;
// IR_OPCODE
static const uint HOST_SERVICE_OPEN_READ = 46u;
// IR_OPCODE
static const uint HOST_SERVICE_OPEN_WRITE = 47u;
// IR_OPCODE
static const uint HOST_SERVICE_OPEN_APPEND = 48u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_STDOUT = 49u;
// IR_OPCODE
static const uint HOST_SERVICE_WRITE_STDERR = 50u;
// IR_OPCODE
static const uint HOST_SERVICE_READ_STDIN = 51u;
// Compiler intrinsics have their own namespace. They must not reuse host
// service slots merely because their declarations occupy builtin-name slots.
// IR_OPCODE
static const uint INTRINSIC_I32_ARRAY_DATA_PTR = 3u;
// IR_OPCODE
static const uint HOST_SERVICE_FILL_SECURE_BYTES = 53u;
// IR_OPCODE
static const uint HOST_SERVICE_REMOVE_FILE = 54u;
// IR_OPCODE
static const uint HOST_SERVICE_CREATE_DIR = 55u;
// IR_OPCODE
static const uint HOST_SERVICE_REMOVE_DIR = 56u;
// IR_OPCODE
static const uint HOST_SERVICE_RENAME = 57u;
// IR_OPCODE
static const uint HOST_SERVICE_MONOTONIC_READ = 58u;
// IR_OPCODE
static const uint HOST_SERVICE_SYSTEM_READ = 59u;
// IR_OPCODE
static const uint HOST_SERVICE_SLEEP_MS_I32 = 60u;
// IR_OPCODE
static const uint HOST_SERVICE_REALLOC = 61u;
// IR_OPCODE
static const uint HOST_SERVICE_ALLOC_FAILED = 62u;
// IR_OPCODE
static const uint HOST_SERVICE_FIRST = 20u;
// IR_OPCODE
static const uint HOST_SERVICE_END = 63u;

// Semantic rows are never silently discarded merely because a target does
// not implement them yet.  The lowering diagnostic reduction treats this as
// a hard compiler error before artifact publication.
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_UNSUPPORTED = 1u;
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL = 2u;
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_BRANCH_CONTINUE = 4u;
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID = 8u;
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_BRANCH_FALSE = 16u;
// LOAD/STORE addresses are `(aggregate, index)` rather than scalar pointers.
// The target layer owns concrete element stride and memory representation.
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_INDEXED = 32u;
// LOAD/STORE addresses are `(aggregate, canonical field ordinal)`. Concrete
// byte offsets belong to the target layout layer, not semantic lowering.
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_FIELD = 64u;
// A `for` row whose checked iterable has no range/array lowering recipe.
static const uint SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE = 128u;
// Effectful RHS operations require conditional scheduling before logical
// AND/OR may be lowered eagerly by a target.
static const uint SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_CALL = 256u;
static const uint SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_TRAP = 512u;
// IR_OPCODE
static const uint SEMANTIC_LIR_FLAG_UNSUPPORTED_MATCH_CONTEXT = 1024u;

// Canonical type-reference tags shared with checked semantic artifacts.
static const uint SEMANTIC_TYPE_REF_INVALID = 0u;
static const uint SEMANTIC_TYPE_REF_SCALAR = 1u;
static const uint SEMANTIC_TYPE_REF_INSTANCE = 3u;

// Function ABI flags are separate from instruction flags.
// IR_OPCODE
static const uint SEMANTIC_FUNCTION_FLAG_ENTRYPOINT = 1u;
static const uint SEMANTIC_FUNCTION_FLAG_EXTERN = 2u;

// IR_OPCODE
static const uint LOWERING_STATUS_SEMANTIC_CAPACITY = 1u;
// IR_OPCODE
static const uint LOWERING_STATUS_TARGET_CAPACITY = 2u;
// IR_OPCODE
static const uint LOWERING_STATUS_ARTIFACT_CAPACITY = 4u;
// IR_OPCODE
static const uint LOWERING_STATUS_UNSUPPORTED_SEMANTIC = 8u;
// IR_OPCODE
static const uint LOWERING_STATUS_UNSUPPORTED_TARGET = 16u;
// IR_OPCODE
static const uint LOWERING_STATUS_AGGREGATE_CAPACITY = 32u;
// IR_OPCODE
static const uint LOWERING_STATUS_STRING_CAPACITY = 64u;
// IR_OPCODE
static const uint LOWERING_STATUS_MULTIPLE_ENTRYPOINTS = 128u;
// IR_OPCODE
static const uint LOWERING_STATUS_MISSING_ENTRYPOINT = 256u;

// Target-validation diagnostics carried across the GPU lowering boundary.
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_NONE = 0u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_PARAMETERS = 1u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_AGGREGATE_RETURN = 2u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_PARAMETER_REGISTERS = 3u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_CALL_ABI = 4u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_MISSING_ENTRYPOINT = 5u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_MULTIPLE_ENTRYPOINTS = 6u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_FOR_ITERABLE = 7u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_ZERO_DIVISOR = 8u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_ARRAY_INDEX_BOUNDS = 9u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_DYNAMIC_ARRAY_INDEX = 10u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_CALL = 11u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_TRAP = 12u;
// IR_OPCODE
static const uint LOWERING_DIAGNOSTIC_X86_MATCH_EXPRESSION = 13u;

// Diagnostic details either name a source token directly or a compact HIR
// row whose token anchor must be read from compact HIR.
static const uint LOWERING_DIAGNOSTIC_DETAIL_NONE = 0u;
static const uint LOWERING_DIAGNOSTIC_DETAIL_TOKEN = 1u;
static const uint LOWERING_DIAGNOSTIC_DETAIL_HIR = 2u;

// x86 target LIR is the backend's uniform virtual-instruction vocabulary.
// IR_OPCODE
static const uint X86_LIR_OP_IMM_I32 = 1u;
// IR_OPCODE
static const uint X86_LIR_OP_UNARY = 3u;
// IR_OPCODE
static const uint X86_LIR_OP_BINARY = 4u;
// IR_OPCODE
static const uint X86_LIR_OP_COMPARE = 5u;
// IR_OPCODE
static const uint X86_LIR_OP_ALIAS = 8u;
// IR_OPCODE
static const uint X86_LIR_OP_RETURN = 9u;
// IR_OPCODE
static const uint X86_LIR_OP_BRANCH = 10u;
// Conditional control transfer whose condition is an integer comparison.
// The compare result is never materialized: local_ordinal is the comparison
// predicate, result_or_target is the branch target, and operands A/B are the
// compared values. The branch is taken when the predicate is false.
// IR_OPCODE
static const uint X86_LIR_OP_COMPARE_BRANCH_FALSE = 11u;
// Branch-free lowering of a pure scalar assignment diamond. The false-arm
// store executes normally; this row compares A/B and conditionally replaces
// that stored value with C. result_or_target retains the declaration token.
// IR_OPCODE
static const uint X86_LIR_OP_SELECT_STORE = 12u;
// IR_OPCODE
static const uint X86_LIR_OP_STORE_LOCAL = 14u;
// IR_OPCODE
static const uint X86_LIR_OP_CALL = 20u;
// One independently lowered SysV argument placement. These rows immediately
// precede their CALL row and allow argument ABI work to run one GPU lane per
// argument instead of serializing an arbitrary argument list in one lane.
// IR_OPCODE
static const uint X86_LIR_OP_CALL_ARG = 21u;
// Target-specific runtime-service call. Operand A is the stable semantic host
// service ID, never a source token or a machine address.
// IR_OPCODE
static const uint X86_LIR_OP_CALL_HOST = 22u;
// Relocatable call whose operands retain the canonical symbol identity.
// IR_OPCODE
static const uint X86_LIR_OP_CALL_SYMBOL = 23u;
// IR_OPCODE
static const uint X86_LIR_OP_RETURN_VOID = 24u;
// Fixed-frame aggregate storage. AGGREGATE_ADDR produces the address of the
// contiguous value rows; AGGREGATE_INIT owns one independently emitted field.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_ADDR = 30u;
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_INIT = 31u;
// IR_OPCODE
static const uint X86_LIR_OP_INDEX_LOAD = 32u;
// IR_OPCODE
static const uint X86_LIR_OP_FIELD_LOAD = 33u;
// Target-only frame row reserved for an aggregate result word. It emits no
// bytes, but gives the caller stable storage for the rest of its activation.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_RESULT_SLOT = 34u;
// One independently emitted aggregate-return word. Register-class results use
// RAX/RDX; memory-class results copy into caller-owned return storage.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_RETURN_WORD = 35u;
// The two target rows of one semantic string constant materialize its rodata
// address and decoded byte length independently for ABI expansion.
// IR_OPCODE
static const uint X86_LIR_OP_STRING_ADDR = 36u;
// IR_OPCODE
static const uint X86_LIR_OP_STRING_LEN = 37u;
// Store through an aggregate address. Operands are receiver, element/field,
// and value; concrete stride belongs to target lowering.
// IR_OPCODE
static const uint X86_LIR_OP_INDEX_STORE = 40u;
// IR_OPCODE
static const uint X86_LIR_OP_FIELD_STORE = 41u;
// One independently lowered word of an aggregate value copy. The destination
// is a frame-resident row owned by the surrounding STORE_LOCAL expansion.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_COPY_WORD = 42u;
// Compiler intrinsic lowered to the native runtime's shared signed-decimal
// printer. Its argument arrives through the ordinary CALL_ARG ABI rows.
// IR_OPCODE
static const uint X86_LIR_OP_PRINT_I32 = 38u;
// Compiler-only identity projection for aggregate pointers. The ordinary
// CALL_ARG row places the source pointer in RDI; this row moves that value
// into the result location without crossing the host-service ABI.
// IR_OPCODE
static const uint X86_LIR_OP_INTRINSIC_IDENTITY = 39u;
// Target-only pseudo instruction. It owns a stable scheduled row for branch
// resolution and is removed by final machine selection.
// IR_OPCODE
static const uint X86_LIR_OP_LABEL = 74u;

// Operation payloads consumed by the existing x86 instruction selector.
// IR_OPCODE
static const uint X86_LIR_UNARY_NEG_I32 = 1u;
// IR_OPCODE
static const uint X86_LIR_UNARY_NOT_BOOL = 2u;
// IR_OPCODE
static const uint X86_LIR_UNARY_NEG_F32 = 3u;
// IR_OPCODE
static const uint X86_LIR_BINARY_ADD_I32 = 1u;
// IR_OPCODE
static const uint X86_LIR_BINARY_SUB_I32 = 2u;
// IR_OPCODE
static const uint X86_LIR_BINARY_MUL_I32 = 3u;
// IR_OPCODE
static const uint X86_LIR_BINARY_AND_BOOL = 4u;
// IR_OPCODE
static const uint X86_LIR_BINARY_OR_BOOL = 5u;
// IR_OPCODE
static const uint X86_LIR_BINARY_REM_I32 = 6u;
// IR_OPCODE
static const uint X86_LIR_BINARY_DIV_I32 = 7u;
// IR_OPCODE
static const uint X86_LIR_BINARY_BIT_AND_I32 = 8u;
// IR_OPCODE
static const uint X86_LIR_BINARY_BIT_OR_I32 = 9u;
// IR_OPCODE
static const uint X86_LIR_BINARY_BIT_XOR_I32 = 10u;
// IR_OPCODE
static const uint X86_LIR_BINARY_SHL_I32 = 11u;
// IR_OPCODE
static const uint X86_LIR_BINARY_SHR_I32 = 12u;
// Division and remainder by a statically known positive power of two. The
// divisor is carried directly in operand C instead of naming a value row.
// Signedness remains the semantic scalar type in operand metadata.
// IR_OPCODE
static const uint X86_LIR_BINARY_DIV_CONST_POW2_I32 = 13u;
// IR_OPCODE
static const uint X86_LIR_BINARY_REM_CONST_POW2_I32 = 14u;
// IR_OPCODE
static const uint X86_LIR_BINARY_ADD_F32 = 16u;
// IR_OPCODE
static const uint X86_LIR_BINARY_SUB_F32 = 17u;
// IR_OPCODE
static const uint X86_LIR_BINARY_MUL_F32 = 18u;
// IR_OPCODE
static const uint X86_LIR_BINARY_DIV_F32 = 19u;
// Signed division and remainder by a statically known positive non-power-of-
// two divisor. Operand C carries the divisor; instruction selection derives
// the multiplier and shift without retaining the constant producer.
// IR_OPCODE
static const uint X86_LIR_BINARY_DIV_CONST_I32 = 20u;
// IR_OPCODE
static const uint X86_LIR_BINARY_REM_CONST_I32 = 21u;

// Wasm target-IR opcodes intentionally equal their final primary opcode byte.
// IR_OPCODE
static const uint WASM_LIR_OP_UNREACHABLE = 0x00u;
// IR_OPCODE
static const uint WASM_LIR_OP_BLOCK = 0x02u;
// IR_OPCODE
static const uint WASM_LIR_OP_LOOP = 0x03u;
// IR_OPCODE
static const uint WASM_LIR_OP_IF = 0x04u;
// IR_OPCODE
static const uint WASM_LIR_OP_ELSE = 0x05u;
// IR_OPCODE
static const uint WASM_LIR_OP_END = 0x0bu;
// IR_OPCODE
static const uint WASM_LIR_OP_BRANCH = 0x0cu;
// IR_OPCODE
static const uint WASM_LIR_OP_BRANCH_IF = 0x0du;
// IR_OPCODE
static const uint WASM_LIR_OP_GLOBAL_GET = 0x23u;
// IR_OPCODE
static const uint WASM_LIR_OP_GLOBAL_SET = 0x24u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LOAD = 0x28u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_LOAD = 0x2au;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_STORE = 0x36u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_STORE = 0x38u;
// IR_OPCODE
static const uint WASM_LIR_OP_RETURN = 0x0fu;
// IR_OPCODE
static const uint WASM_LIR_OP_CALL = 0x10u;
// IR_OPCODE
static const uint WASM_LIR_OP_DROP = 0x1au;
// IR_OPCODE
static const uint WASM_LIR_OP_LOCAL_GET = 0x20u;
// IR_OPCODE
static const uint WASM_LIR_OP_LOCAL_SET = 0x21u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_CONST = 0x41u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_CONST = 0x43u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_EQZ = 0x45u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_EQ = 0x46u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_NE = 0x47u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LT_S = 0x48u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LT_U = 0x49u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_GT_S = 0x4au;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_GT_U = 0x4bu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LE_S = 0x4cu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LE_U = 0x4du;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_GE_S = 0x4eu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_GE_U = 0x4fu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_EQ = 0x5bu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_NE = 0x5cu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_LT = 0x5du;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_GT = 0x5eu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_LE = 0x5fu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_GE = 0x60u;
// Pseudo-op retained until the Wasm module/import ABI assigns a concrete
// function index. It must never be emitted as a byte opcode directly.
// IR_OPCODE
static const uint WASM_LIR_OP_CALL_HOST = 0x100u;
// Relocatable call. This pseudo-op emits `call` plus a fixed-width padded LEB
// placeholder; WasmLirOperands retain the canonical symbol identity.
// IR_OPCODE
static const uint WASM_LIR_OP_CALL_SYMBOL = 0x101u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_ADD = 0x6au;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_SUB = 0x6bu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_MUL = 0x6cu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_DIV_S = 0x6du;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_REM_S = 0x6fu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_AND = 0x71u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_OR = 0x72u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_XOR = 0x73u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_SHL = 0x74u;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_SHR_S = 0x75u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_NEG = 0x8cu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_ADD = 0x92u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_SUB = 0x93u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_MUL = 0x94u;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_DIV = 0x95u;
// IR_OPCODE
static const uint WASM_LIR_OP_I64_EXTEND_I32_S = 0xacu;
// IR_OPCODE
static const uint WASM_LIR_OP_F32_CONVERT_I32_S = 0xb2u;

// IR_OPCODE
static const uint TARGET_LIR_FLAG_UNSUPPORTED = 1u;
// The instruction carries a five-byte linear-memory data relocation rather
// than a function-index relocation. The linker rewrites its immediate after
// concatenating unit string pools.
static const uint TARGET_LIR_FLAG_DATA_RELOCATION = 2u;
// x86 operand metadata: the value uses the aggregate-reference ABI. This is
// derived from the full checked type before scalar type IDs are compacted.
// IR_OPCODE
static const uint X86_LIR_METADATA_AGGREGATE = 0x80000000u;
// The value occupies one ABI register, but that register carries a full
// machine word (for example the address half of a string pair).
static const uint X86_LIR_METADATA_WIDE = 0x40000000u;
// The second machine word of a string value is its decoded byte length. It
// has a separate target-row home from the pointer word and is passed as a
// normal 32-bit ABI argument.
static const uint X86_LIR_METADATA_STRING_LEN = 0x20000000u;
// The compared value is pointer-width, but its RHS is a narrow integer null
// constant. Keeping this in target metadata avoids weakening semantic types.
static const uint X86_LIR_METADATA_RHS_NARROW = 0x10000000u;
// One target operand is an immediate machine word rather than a semantic
// value. AGGREGATE_INIT uses operand A; integer binary and compare operations
// use operand C. Keeping this explicit prevents resolve/location passes from
// treating literal bits as a target-row reference.
static const uint X86_LIR_METADATA_IMMEDIATE = 0x08000000u;
// The instruction belongs to a native string's pointer/length pair. This is
// deliberately explicit: concrete aggregate type IDs may share their low byte
// with a primitive type tag and must never be classified by truncation.
static const uint X86_LIR_METADATA_STRING_PAIR = 0x04000000u;

// Semantic AGGREGATE_NEW metadata. The high bit distinguishes tagged enums;
// the remaining bits contain the checked variant ordinal.
static const uint SEMANTIC_LIR_AGGREGATE_ENUM = 0x80000000u;
static const uint SEMANTIC_LIR_AGGREGATE_TAG_MASK = 0x7fffffffu;

// A value location is either a target-row stack home or a physical x86 GPR.
// Stack payloads remain global target rows; the artifact emitter translates
// them to function-relative frame slots after target paging has been replayed.
// IR_OPCODE
static const uint X86_LOCATION_REGISTER = 0x80000000u;
// During allocation, a scalar producer immediately assigned to a declaration
// may name that declaration instead of receiving a temporary home. The later
// location pass resolves the dense token to its physical register or stack
// slot after declaration allocation has completed.
// IR_OPCODE
static const uint X86_LOCATION_DECLARATION = 0x40000000u;
// IR_OPCODE
static const uint X86_LOCATION_PAYLOAD_MASK = 0x3fffffffu;
// IR_OPCODE
static const uint X86_LOCATION_INVALID = 0xffffffffu;
static const uint X86_DECLARATION_MULTIPLE_DEFINITIONS = 0xfffffffeu;

// x86 semantic-row states. Nonzero rows survive target-LIR compaction; the
// specialized states also carry optimizer decisions into later location and
// instruction-selection passes without another semantic-sized buffer.
static const uint X86_SEMANTIC_LIVE = 1u;
static const uint X86_SEMANTIC_SELECT = 2u;
static const uint X86_SEMANTIC_COALESCED_ALIAS = 4u;
static const uint X86_SEMANTIC_COMPARE_ALIAS_BRANCH = 8u;

static const uint X86_FUNCTION_REGISTER_DIRECT_ABI_HOMES = 1u;
static const uint X86_FUNCTION_REGISTER_CALL_WITH_LOOP = 2u;

// Allocatable caller-saved registers for short semantic value lifetimes.
// Their cyclic assignment is sound for intervals shorter than this count.
// IR_OPCODE
static const uint X86_TEMP_REGISTER_COUNT = 4u;
// IR_OPCODE
static const uint X86_TEMP_REGISTER_FIRST = 8u;

struct SemanticLirCore
{
    uint type_id;
    // Canonical checked type identity. `type_id` remains the compact machine
    // class used by instruction selection; aggregate identity and generic
    // structure live in the payload and the two high flag bits instead of a
    // mostly empty word in every instruction.
    uint type_ref_payload;
    uint flags;
    // Fixed-size aggregate width in machine words. Scalar rows use zero.
    uint value_word_count;
};

static const uint SEMANTIC_LIR_TYPE_REF_TAG_SHIFT = 30u;
static const uint SEMANTIC_LIR_TYPE_REF_TAG_MASK = 3u << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT;
static const uint SEMANTIC_LIR_OP_SHIFT = 24u;
static const uint SEMANTIC_LIR_OP_MASK = 0x3fu << SEMANTIC_LIR_OP_SHIFT;

uint semantic_lir_op(SemanticLirCore core)
{
    return (core.flags & SEMANTIC_LIR_OP_MASK) >> SEMANTIC_LIR_OP_SHIFT;
}

uint semantic_lir_type_ref_tag(SemanticLirCore core)
{
    return (core.flags & SEMANTIC_LIR_TYPE_REF_TAG_MASK) >>
        SEMANTIC_LIR_TYPE_REF_TAG_SHIFT;
}

struct SemanticLirOperands
{
    uint result;
    uint a;
    uint b;
    uint c;
};

struct SemanticLirCallArg
{
    uint call_instruction;
    uint value_instruction;
    uint ordinal;
    uint value_metadata;
};

struct SemanticLirAggregateElement
{
    uint aggregate_instruction;
    uint value_instruction;
    uint ordinal;
    uint name_token;
    uint value_metadata;
    uint word_offset;
    uint word_count;
};

struct TargetSemanticPage
{
    uint semantic_start;
    uint semantic_count;
    uint target_start;
    uint target_count;
};

static const uint SEMANTIC_LIR_VALUE_TYPE_MASK = 0x00ffffffu;
static const uint SEMANTIC_LIR_VALUE_AGGREGATE = 1u << 24u;
static const uint SEMANTIC_LIR_VALUE_STRING = 1u << 25u;

uint semantic_lir_value_metadata(uint type_id, uint type_ref_tag,
                                 uint type_ref_payload)
{
    bool aggregate = type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         type_ref_payload >= 128u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && type_id >= 128u);
    bool string_value =
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR && type_ref_payload == 7u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && type_id == 7u);
    return (type_id & SEMANTIC_LIR_VALUE_TYPE_MASK) |
        (aggregate ? SEMANTIC_LIR_VALUE_AGGREGATE : 0u) |
        (string_value ? SEMANTIC_LIR_VALUE_STRING : 0u);
}

struct SemanticLirString
{
    uint instruction;
    uint data_offset;
    uint decoded_len;
    uint file_id;
};

struct SemanticLirFunction
{
    uint hir_function;
    uint name_token;
    uint param_start;
    uint param_count;
    uint result_type;
    uint flags;
    uint file_id;
    uint local_start;
    uint local_count;
    uint result_word_count;
    // Stable declaration index in the unit's semantic interface. The target
    // object layer combines this with its library/unit identity.
    uint symbol_local_index;
    uint symbol_flags;
    uint host_service;
};

struct SemanticLirParam
{
    uint function_id;
    uint declaration_id;
    uint ordinal;
    uint type_id;
};

struct SemanticLirLocal
{
    uint function_id;
    uint declaration_id;
    uint ordinal;
    uint type_id;
};

struct SemanticLirSchedule
{
    uint execution_region;
    uint execution_rank;
    uint execution_tie;
};

struct LoweringStatus
{
    uint flags;
    uint first_unsupported_hir;
    uint required_capacity;
    uint available_capacity;
    uint diagnostic_reason;
    uint diagnostic_detail_kind;
    uint diagnostic_detail;
    uint diagnostic_aux;
};

// Capacity-packed lexicographic target scheduling key. Fields are encoded in
// least-significant order as execution tie, execution rank, execution region,
// then function ID. The radix stage consumes the packed bytes directly.
struct TargetScheduleKey
{
    uint word0;
    uint word1;
    uint word2;
};

// Compact ranges over the target's final scheduled instruction stream.  Both
// backends consume this table, so module/body assembly and native function
// emission do not rediscover function boundaries independently.
struct TargetLirFunction
{
    uint function_id;
    uint instruction_start;
    uint instruction_count;
    uint flags;
};

// x86 specializes the shared flags word after target-function construction.
// The low bits hold the compact frame-slot count; the high bit records that
// the function has no calls or stack-resident values and may omit RBP setup.
static const uint X86_TARGET_FUNCTION_FRAMELESS = 0x80000000u;
static const uint X86_TARGET_FUNCTION_STACKLESS_CALLER = 0x40000000u;
static const uint X86_TARGET_FUNCTION_FRAME_SLOT_MASK = 0x3fffffffu;

// This is the existing x86 virtual-instruction physical layout, now named as
// the target-specific second lowering level.
struct X86LirCore
{
    uint source_hir;
    uint local_ordinal;
    uint op;
    uint result_or_target;
};

struct X86LirOperands
{
    uint a;
    uint b;
    uint c;
    uint metadata;
};

// Physical homes corresponding to result/a/b/c. Non-value operand fields use
// X86_LOCATION_INVALID. This stays page-local alongside x86 target LIR.
struct X86LirLocations
{
    uint result;
    uint a;
    uint b;
    uint c;
};

struct X86SelectInfo
{
    uint condition;
    uint true_value;
    uint false_value;
    uint declaration;
};

struct X86DeclarationAnalysis
{
    uint last_read;
    uint last_access;
    uint definition;
    uint read_count;
};

struct X86FunctionRegisterAnalysis
{
    uint first_call;
    uint first_rdx_clobber;
    uint first_rcx_clobber;
    uint flags;
};

struct X86ValueAnalysis
{
    uint value;
    uint known;
    uint replacement;
};

struct WasmLirInstruction
{
    uint opcode;
    uint immediate;
    uint semantic_instruction;
    uint flags;
};

struct WasmLirOperands
{
    uint a;
    uint b;
    uint c;
    uint metadata;
};

struct WasmLirFunction
{
    uint semantic_function;
    uint type_index;
    uint param_value_count;
    uint local_value_count;
    uint body_instruction_start;
    uint body_instruction_count;
    uint body_byte_start;
    uint body_byte_count;
    uint flags;
    uint result_type;
    uint param_start;
    uint param_count;
    uint local_start;
    uint local_count;
};

struct WasmModuleLayout
{
    uint function_count;
    uint entrypoint_count;
    uint entrypoint_id;
    uint status;
    uint module_length;
    uint type_section_start;
    uint type_entries_start;
    uint type_entries_length;
    uint function_section_start;
    uint function_entries_start;
    uint export_section_start;
    uint code_section_start;
    uint code_entries_start;
    uint code_entries_length;
    uint reserved0;
    uint reserved1;
};

struct WasmObjectRelocationRow
{
    uint body_byte_offset;
    uint target_kind;
    uint target_index;
    uint addend;
    uint library_id;
    uint unit_id;
    uint local_index;
    uint reserved;
};

struct WasmObjectFunctionRow
{
    uint type_byte_start;
    uint type_byte_len;
    uint body_byte_start;
    uint body_byte_len;
    uint symbol_index;
    uint flags;
};

struct WasmObjectDefinitionRow
{
    uint library_id;
    uint unit_id;
    uint local_index;
    uint function_index;
    uint size;
    uint flags;
    uint reserved0;
    uint reserved1;
};

struct X86ObjectRelocationRow
{
    uint kind;
    uint site_section;
    uint site_offset;
    uint target_kind;
    uint target_index;
    uint target_offset;
    uint addend_lo;
    uint addend_hi;
};

struct X86ObjectDefinitionRow
{
    uint library_id;
    uint unit_id;
    uint local_index;
    uint section;
    uint offset;
    uint size;
    uint flags;
    uint reserved;
};

struct X86ObjectUndefinedRow
{
    uint library_id;
    uint unit_id;
    uint local_index;
    uint reserved;
};

struct X86ArtifactLayout
{
    uint body_length;
    uint file_length;
    uint entrypoint_count;
    uint entrypoint_function;
    uint entrypoint_body_offset;
    uint text_offset;
    uint body_offset;
    uint status;
    uint runtime_offset;
    uint runtime_length;
    uint rodata_offset;
    uint rodata_length;
};
