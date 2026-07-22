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
// Slot 52 is a compiler-only address projection, not a runtime service.
// IR_OPCODE
static const uint HOST_SERVICE_I32_ARRAY_DATA_PTR = 52u;
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

// Canonical type-reference tags shared with checked semantic artifacts.
static const uint SEMANTIC_TYPE_REF_INVALID = 0u;
static const uint SEMANTIC_TYPE_REF_SCALAR = 1u;
static const uint SEMANTIC_TYPE_REF_GENERIC_PARAM = 2u;
static const uint SEMANTIC_TYPE_REF_INSTANCE = 3u;
static const uint SEMANTIC_TYPE_REF_ERROR = 4u;

// Function ABI flags are separate from instruction flags.
// IR_OPCODE
static const uint SEMANTIC_FUNCTION_FLAG_ENTRYPOINT = 1u;
// IR_OPCODE
static const uint SEMANTIC_FUNCTION_FLAG_PUBLIC = 2u;

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

// x86 target LIR is the backend's uniform virtual-instruction vocabulary.
// IR_OPCODE
static const uint X86_LIR_OP_IMM_I32 = 1u;
// IR_OPCODE
static const uint X86_LIR_OP_PARAM = 2u;
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
// IR_OPCODE
static const uint X86_LIR_OP_LOOP = 11u;
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
// Fixed-frame aggregate storage. ARRAY_ADDR produces the address of the
// contiguous element rows; ARRAY_INIT owns one independently emitted element.
// IR_OPCODE
static const uint X86_LIR_OP_ARRAY_ADDR = 30u;
// IR_OPCODE
static const uint X86_LIR_OP_ARRAY_INIT = 31u;
// IR_OPCODE
static const uint X86_LIR_OP_INDEX_LOAD = 32u;
// IR_OPCODE
static const uint X86_LIR_OP_FIELD_LOAD = 33u;
// Target-only frame row reserved for aggregate results returned in registers.
// It emits no machine bytes, but gives each returned word stable caller-owned
// storage for the remainder of the caller's activation.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_RESULT_SLOT = 34u;
// One independently emitted aggregate-return word. Register-class returns
// place it in EAX/EDX; sret-class returns copy it to caller-owned storage.
// IR_OPCODE
static const uint X86_LIR_OP_AGGREGATE_RETURN_WORD = 35u;
// The two target rows of one semantic string constant materialize its rodata
// address and decoded byte length independently for ABI expansion.
// IR_OPCODE
static const uint X86_LIR_OP_STRING_ADDR = 36u;
// IR_OPCODE
static const uint X86_LIR_OP_STRING_LEN = 37u;
// Compiler intrinsic lowered to the native runtime's shared signed-decimal
// printer. Its argument arrives through the ordinary CALL_ARG ABI rows.
// IR_OPCODE
static const uint X86_LIR_OP_PRINT_I32 = 38u;
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
// IR_OPCODE
static const uint X86_LIR_BINARY_ADD_F32 = 16u;
// IR_OPCODE
static const uint X86_LIR_BINARY_SUB_F32 = 17u;
// IR_OPCODE
static const uint X86_LIR_BINARY_MUL_F32 = 18u;
// IR_OPCODE
static const uint X86_LIR_BINARY_DIV_F32 = 19u;

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
// x86 operand metadata: the value uses the aggregate-reference ABI. This is
// derived from the full checked type before scalar type IDs are compacted.
// IR_OPCODE
static const uint X86_LIR_METADATA_AGGREGATE = 0x80000000u;
// The value occupies one ABI register, but that register carries a full
// machine word (for example the address half of a string pair).
static const uint X86_LIR_METADATA_WIDE = 0x40000000u;

struct SemanticLirCore
{
    uint op;
    uint type_id;
    // Canonical checked type identity. `type_id` remains the compact machine
    // class used by instruction selection; aggregate identity and generic
    // structure live in this tag/payload pair instead of numeric heuristics.
    uint type_ref_tag;
    uint type_ref_payload;
    uint source_hir;
    uint flags;
};

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
    uint flags;
};

struct SemanticLirAggregateElement
{
    uint aggregate_instruction;
    uint value_instruction;
    uint ordinal;
    uint name_token;
};

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
    uint function_id;
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
};

// Lexicographic target scheduling key. The eventual radix stage processes the
// words from `execution_tie` back to `function_id` with stable passes.
struct TargetScheduleKey
{
    uint function_id;
    uint execution_region;
    uint execution_rank;
    uint execution_tie;
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
