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
static const uint WASM_LIR_OP_I32_GT_S = 0x4au;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_LE_S = 0x4cu;
// IR_OPCODE
static const uint WASM_LIR_OP_I32_GE_S = 0x4eu;
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
static const uint WASM_LIR_OP_F32_CONVERT_I32_S = 0xb2u;

// IR_OPCODE
static const uint TARGET_LIR_FLAG_UNSUPPORTED = 1u;
// x86 operand metadata: the value uses the aggregate-reference ABI. This is
// derived from the full checked type before scalar type IDs are compacted.
// IR_OPCODE
static const uint X86_LIR_METADATA_AGGREGATE = 0x80000000u;

struct SemanticLirCore
{
    uint op;
    uint type_id;
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
    uint reserved0;
    uint reserved1;
    uint reserved2;
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
};
