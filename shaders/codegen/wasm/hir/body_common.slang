// Shared helpers for the small HIR-driven WASM body pipeline.
//
// This handles the scalar entrypoint slice the module wrapper supports. Other
// shapes continue to fail closed with the stable WASM backend boundary. Body
// emission uses per-node fragment records followed by prefix-scan/scatter
// passes.

import gpu_index;
import call_relocation;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint artifact_flags;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> hir_array_lit_first_element;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_array_element_next;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_start;
StructuredBuffer<uint> hir_struct_lit_field_count;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> hir_struct_lit_field_next;
StructuredBuffer<uint> struct_init_field_index;
StructuredBuffer<uint> struct_init_field_decl_node_by_node;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> hir_nearest_block_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint2> expr_subtree_total;
StructuredBuffer<uint2> expr_subtree_features;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;

RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_return_count_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_return_token_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint LANGUAGE_SYMBOL_READ_I32 = 22u;
static const uint LANGUAGE_SYMBOL_OPEN_READ_PATH = 20u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint LANGUAGE_SYMBOL_WRITE_I32 = 24u;
static const uint LANGUAGE_SYMBOL_WRITE_BYTE = 25u;
static const uint LANGUAGE_SYMBOL_WRITE_NEWLINE = 26u;
static const uint LANGUAGE_SYMBOL_CLOSE_FILE = 27u;
static const uint LANGUAGE_SYMBOL_EXIT = 29u;
static const uint LANGUAGE_SYMBOL_SECURE_U32 = 30u;
static const uint LANGUAGE_SYMBOL_ALLOC = 31u;
static const uint LANGUAGE_SYMBOL_DEALLOC = 32u;
static const uint LANGUAGE_SYMBOL_ARGC = 33u;
static const uint LANGUAGE_SYMBOL_ARG_LEN = 34u;
static const uint LANGUAGE_SYMBOL_ARG_READ = 35u;
static const uint LANGUAGE_SYMBOL_UNIX_SECONDS = 36u;
static const uint LANGUAGE_SYMBOL_CURRENT_DIR_READ = 37u;
static const uint LANGUAGE_SYMBOL_VAR_COUNT = 38u;
static const uint LANGUAGE_SYMBOL_VAR_KEY_LEN = 39u;
static const uint LANGUAGE_SYMBOL_VAR_KEY_READ = 40u;
static const uint LANGUAGE_SYMBOL_VAR_LEN = 41u;
static const uint LANGUAGE_SYMBOL_VAR_READ = 42u;
static const uint LANGUAGE_SYMBOL_CLOSE = 43u;
static const uint LANGUAGE_SYMBOL_READ = 44u;
static const uint LANGUAGE_SYMBOL_WRITE = 45u;
static const uint LANGUAGE_SYMBOL_OPEN_READ = 46u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE = 47u;
static const uint LANGUAGE_SYMBOL_OPEN_APPEND = 48u;
static const uint LANGUAGE_SYMBOL_WRITE_STDOUT = 49u;
static const uint LANGUAGE_SYMBOL_WRITE_STDERR = 50u;
static const uint LANGUAGE_SYMBOL_READ_STDIN = 51u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;
static const uint LANGUAGE_SYMBOL_FILL_SECURE_BYTES = 53u;
static const uint LANGUAGE_SYMBOL_REMOVE_FILE = 54u;
static const uint LANGUAGE_SYMBOL_CREATE_DIR = 55u;
static const uint LANGUAGE_SYMBOL_REMOVE_DIR = 56u;
static const uint LANGUAGE_SYMBOL_RENAME = 57u;
static const uint LANGUAGE_SYMBOL_MONOTONIC_READ = 58u;
static const uint LANGUAGE_SYMBOL_SYSTEM_READ = 59u;
static const uint LANGUAGE_SYMBOL_SLEEP_MS_I32 = 60u;
static const uint LANGUAGE_SYMBOL_REALLOC = 61u;
static const uint LANGUAGE_SYMBOL_ALLOC_FAILED = 62u;
static const uint HOST_STR_CALL_OPEN_READ_PATH = 1u;
static const uint HOST_STR_CALL_OPEN_WRITE_PATH = 2u;
static const uint HOST_STR_CALL_WRITE_TEXT = 3u;

static const uint ENTRYPOINT_MAIN = 1u;
static const uint HIR_NONE = 0u;
static const uint HIR_FN = 3u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_PATH_EXPR = 33u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint STMT_RECORD_KIND_BREAK = 8u;
static const uint STMT_RECORD_KIND_CONTINUE = 9u;

static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INDEX_FORM = 26u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;

static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_WRITE_STDOUT_FUNC_INDEX = 1u;
static const uint WASM_PROCESS_ARGC_FUNC_INDEX = 2u;
static const uint WASM_PROCESS_ARG_LEN_FUNC_INDEX = 3u;
static const uint WASM_PROCESS_ARG_READ_FUNC_INDEX = 4u;
static const uint WASM_RANDOM_SECURE_U32_FUNC_INDEX = 5u;
static const uint WASM_TIME_UNIX_SECONDS_FUNC_INDEX = 6u;
static const uint WASM_ENV_CURRENT_DIR_READ_FUNC_INDEX = 7u;
static const uint WASM_ENV_CURRENT_DIR_LEN_FUNC_INDEX = 8u;
static const uint WASM_ENV_VAR_COUNT_FUNC_INDEX = 9u;
static const uint WASM_ENV_VAR_KEY_LEN_FUNC_INDEX = 10u;
static const uint WASM_ENV_VAR_KEY_READ_FUNC_INDEX = 11u;
static const uint WASM_ENV_VAR_LEN_FUNC_INDEX = 12u;
static const uint WASM_ENV_VAR_READ_FUNC_INDEX = 13u;
static const uint WASM_FS_CLOSE_FUNC_INDEX = 14u;
static const uint WASM_FS_READ_FUNC_INDEX = 15u;
static const uint WASM_FS_WRITE_FUNC_INDEX = 16u;
static const uint WASM_FS_OPEN_READ_FUNC_INDEX = 17u;
static const uint WASM_FS_OPEN_WRITE_FUNC_INDEX = 18u;
static const uint WASM_FS_OPEN_APPEND_FUNC_INDEX = 19u;
static const uint WASM_STDIO_WRITE_STDERR_FUNC_INDEX = 20u;
static const uint WASM_STDIO_READ_STDIN_FUNC_INDEX = 21u;
static const uint WASM_ALLOC_FUNC_INDEX = 22u;
static const uint WASM_DEALLOC_FUNC_INDEX = 23u;
static const uint WASM_STD_READ_I32_FUNC_INDEX = 24u;
static const uint WASM_STD_WRITE_I32_FUNC_INDEX = 25u;
static const uint WASM_STD_WRITE_BYTE_FUNC_INDEX = 26u;
static const uint WASM_STD_WRITE_NEWLINE_FUNC_INDEX = 27u;
static const uint WASM_STD_OPEN_READ_PATH_FUNC_INDEX = 28u;
static const uint WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX = 29u;
static const uint WASM_STD_WRITE_TEXT_FUNC_INDEX = 30u;
static const uint WASM_RANDOM_FILL_SECURE_BYTES_FUNC_INDEX = 31u;
static const uint WASM_FS_REMOVE_FILE_FUNC_INDEX = 32u;
static const uint WASM_FS_CREATE_DIR_FUNC_INDEX = 33u;
static const uint WASM_FS_REMOVE_DIR_FUNC_INDEX = 34u;
static const uint WASM_FS_RENAME_FUNC_INDEX = 35u;
static const uint WASM_TIME_MONOTONIC_READ_FUNC_INDEX = 36u;
static const uint WASM_TIME_SYSTEM_READ_FUNC_INDEX = 37u;
static const uint WASM_TIME_SLEEP_MS_I32_FUNC_INDEX = 38u;
static const uint WASM_REALLOC_FUNC_INDEX = 39u;
static const uint WASM_ALLOC_FAILED_FUNC_INDEX = 40u;
static const uint WASM_PROCESS_EXIT_FUNC_INDEX = 41u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_BR = 0x0cu;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_CALL = 0x10u;
static const uint WASM_END = 0x0bu;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_F32_EQ = 0x5bu;
static const uint WASM_F32_NE = 0x5cu;
static const uint WASM_F32_LT = 0x5du;
static const uint WASM_F32_GT = 0x5eu;
static const uint WASM_F32_LE = 0x5fu;
static const uint WASM_F32_GE = 0x60u;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_REM_S = 0x6fu;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
static const uint WASM_I32_AND = 0x71u;
static const uint WASM_I32_OR = 0x72u;
static const uint WASM_I32_XOR = 0x73u;
static const uint WASM_I32_SHL = 0x74u;
static const uint WASM_I32_SHR_S = 0x75u;
static const uint BODY_FRAGMENT_NONE = 0u;
static const uint BODY_FRAGMENT_LOCAL_DECL_COUNT = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_RETURN_I32 = 3u;
static const uint BODY_FRAGMENT_LET_CONST_I32 = 4u;
static const uint BODY_FRAGMENT_ASSIGN_CONST_I32 = 5u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32 = 6u;
static const uint BODY_FRAGMENT_PRINT_LOCAL_I64 = 7u;
static const uint BODY_FRAGMENT_RETURN_LOCAL_I32 = 8u;
static const uint BODY_FRAGMENT_LET_EXPR_I32 = 9u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint BODY_FRAGMENT_PRINT_EXPR_I64 = 12u;
static const uint BODY_FRAGMENT_RETURN_EXPR_I32 = 13u;
static const uint BODY_FRAGMENT_WHILE_OPEN_I32 = 14u;
static const uint BODY_FRAGMENT_WHILE_CLOSE = 15u;
static const uint BODY_FRAGMENT_IF_OPEN_I32 = 16u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_FRAGMENT_BRANCH = 19u;
static const uint BODY_FRAGMENT_FOR_OPEN_RANGE_I32 = 20u;
static const uint BODY_FRAGMENT_FOR_CLOSE_RANGE_I32 = 21u;
static const uint BODY_FRAGMENT_FUNCTION_HEADER = 22u;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint BODY_FRAGMENT_FUNCTION_END = 28u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32 = 32u;
static const uint BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR = 33u;
static const uint BODY_FRAGMENT_LET_HOST_NO_ARG_I32 = 34u;
static const uint BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32 = 35u;
static const uint BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32 = 36u;
static const uint BODY_FRAGMENT_LET_HOST_CALL_I32 = 37u;
static const uint BODY_FRAGMENT_HOST_CALL_VOID = 38u;
static const uint BODY_FRAGMENT_LET_HOST_STR_CALL_I32 = 39u;
static const uint BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32 = 41u;
static const uint BODY_FRAGMENT_IF_OPEN_LOCAL_I32 = 42u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FRAGMENT_RETURN_HOST_CALL_I32 = 47u;
static const uint BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32 = 48u;
static const uint BODY_FRAGMENT_DIRECT_CALL_VOID = 59u;
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != INVALID && ty != TY_UNKNOWN)
        return ty;
    uint decl = visible_decl[token];
    if (!valid_token(decl))
        return TY_UNKNOWN;
    ty = visible_type[decl];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint expr_literal_scalar_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint form = row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        EXPR_RECORD_FORM,
        HIR_EXPR_NONE);
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_INT;
    return TY_UNKNOWN;
}

uint local_decl_initializer_expr_type(uint init_expr)
{
    if (!valid_node(init_expr))
        return TY_UNKNOWN;
    uint root = hir_expr_result_root_node[init_expr];
    uint ty = expr_literal_scalar_type(root);
    if (ty != TY_UNKNOWN)
        return ty;
    return expr_literal_scalar_type(init_expr);
}

uint local_decl_initializer_type(uint decl_token)
{
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    return local_decl_initializer_expr_type(init_expr);
}

uint local_decl_type(uint decl_token)
{
    uint ty = local_decl_initializer_type(decl_token);
    if (ty == TY_UNKNOWN)
        ty = visible_type_for_token(decl_token);
    return ty == TY_UNKNOWN ? TY_INT : ty;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return TY_UNKNOWN;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    }

    uint ty = call_param_row_type[row];
    return ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal)
               ? TY_ARRAY_BASE
               : ty;
}

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
}

bool type_is_i32_abi_value(uint ty)
{
    return type_is_i32_value(ty) || ty == TY_STRING || ty >= TY_ARRAY_BASE;
}

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

bool type_is_i32_abi_param(uint fn_token, uint ordinal, uint ty)
{
    return type_is_i32_abi_value(ty) || (ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal));
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
}

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    return local_max == INVALID ? 0u : local_max + 1u;
}

uint wasm_value_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint function_param_abi_count(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;

    uint count = call_param_count[fn_token];
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        total += wasm_value_abi_width(call_param_type_value(fn_token, ordinal));
    return total;
}

uint function_param_abi_ordinal(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return INVALID;

    uint count = call_param_count[fn_token];
    if (ordinal >= count)
        return INVALID;

    uint local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += wasm_value_abi_width(call_param_type_value(fn_token, i));
    return local_index;
}

uint local_decl_fragment_len_from_count(uint local_count)
{
    if (local_count == 0u)
        return 1u;
    uint i32_count = local_count * 2u;
    return 1u + u32_leb_len(i32_count) + 1u + u32_leb_len(local_count) + 1u;
}

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    uint param_count = call_param_count[fn_token];
    if (ordinal == INVALID || ordinal >= param_count)
        return false;

    local_index = function_param_abi_ordinal(fn_token, ordinal);
    if (local_index == INVALID)
        return false;
    return true;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint param_count = function_param_abi_count(fn_token);
    uint local_count = local_decl_count_for_function_token(fn_token);
    local_index = param_count + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
}

bool function_non_param_local_index_for_type(
    uint decl_token,
    uint fn_token,
    uint local_ty,
    out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint param_count = function_param_abi_count(fn_token);
    uint local_count = local_decl_count_for_function_token(fn_token);
    local_index = param_count + decl_token;
    if (local_ty == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
}

bool function_string_len_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[fn_token])
    {
        if (call_param_type_value(fn_token, ordinal) != TY_STRING)
            return false;
        uint ptr_index = function_param_abi_ordinal(fn_token, ordinal);
        if (ptr_index == INVALID)
            return false;
        local_index = ptr_index + 1u;
        return true;
    }

    if (local_decl_type(decl_token) != TY_STRING)
        return false;
    local_index = function_param_abi_count(fn_token) +
                  local_decl_count_for_function_token(fn_token) +
                  decl_token;
    return true;
}

bool function_decl_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    if (function_param_local_index(decl_token, fn_token, local_index))
        return true;
    return function_non_param_local_index(decl_token, fn_token, local_index);
}

bool valid_token_end(uint token)
{
    return token != INVALID && token <= gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
}

bool valid_span_node(uint node)
{
    return valid_node(node) &&
           valid_token(hir_token_pos[node]) &&
           valid_token_end(hir_token_end[node]) &&
           hir_token_pos[node] < hir_token_end[node];
}

bool node_span_contains(uint owner, uint node)
{
    return valid_span_node(owner) &&
           valid_span_node(node) &&
           hir_token_pos[owner] <= hir_token_pos[node] &&
           hir_token_end[node] <= hir_token_end[owner];
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    return expr_form(node) == HIR_EXPR_FORWARD ? INVALID : node;
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_PATH_EXPR)
        return callee_node;
    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && hir_kind[child] == HIR_PATH_EXPR)
            return child;
    }
    return INVALID;
}

uint path_leaf_token_for_callee(uint callee_node)
{
    uint path_node = path_node_for_callee(callee_node);
    if (!valid_node(path_node))
        return INVALID;

    uint owner_token = hir_token_pos[path_node];
    uint path_i = valid_token(owner_token) ? path_id_by_owner_token[owner_token] : INVALID;
    if (!valid_path(path_i))
        return INVALID;

    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;

    uint slot = path_segment_base[path_i] + count - 1u;
    if (slot >= gParams.n_tokens * MAX_PATH_SEGMENTS)
        return INVALID;

    uint token = path_segment_token[slot];
    return valid_token(token) ? token : INVALID;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint raw_callee_node = hir_call_callee_node[call_node];
    uint path_leaf = path_leaf_token_for_callee(raw_callee_node);
    if (valid_token(path_leaf))
        return path_leaf;

    uint callee_node = resolve_expr_node(raw_callee_node);
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_site_token(uint call_node)
{
    return valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
}

uint semantic_callee_token_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = call_site_token(call_node);
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_metadata_token(uint call_node, uint callee_token)
{
    uint site_token = call_site_token(call_node);
    uint semantic_token = semantic_callee_token_for_call(call_node);

    // Dependency identity is authoritative even when a path/call-site token
    // also carries the local call-pipeline's compatibility projection.
    if (valid_token(site_token) && call_dependency_decl[site_token] != INVALID)
        return site_token;
    if (valid_token(semantic_token) && call_dependency_decl[semantic_token] != INVALID)
        return semantic_token;
    if (valid_token(callee_token) && call_dependency_decl[callee_token] != INVALID)
        return callee_token;

    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return site_token;
    if (valid_token(semantic_token) && valid_token(call_fn_index[semantic_token]))
        return semantic_token;
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;

    return callee_token;
}

uint call_fn_token_for_call(uint call_node, uint callee_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    if (!valid_token(metadata_token))
        return INVALID;
    if (call_dependency_decl[metadata_token] != INVALID)
        return metadata_token;
    uint local_fn = call_fn_index[metadata_token];
    return valid_token(local_fn) ? local_fn : INVALID;
}

bool dependency_call_token(uint token)
{
    return valid_token(token) && call_dependency_decl[token] != INVALID;
}

bool supported_call_target_token(uint token)
{
    return supported_function_token(token) || dependency_call_token(token);
}

uint wasm_call_target_for_call(uint call_node, uint fn_token)
{
    uint metadata_token = call_metadata_token(call_node, call_callee_token(call_node));
    if (valid_token(metadata_token) && call_dependency_decl[metadata_token] != INVALID)
        return 0x80000000u | (call_dependency_decl[metadata_token] & 0x7fffffffu);
    return valid_token(fn_token) && wasm_func_slot_by_token[fn_token] != INVALID
               ? wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT
               : INVALID;
}

uint call_return_type_for_call(uint call_node, uint callee_token, uint fn_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    uint metadata_return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : TY_UNKNOWN;
    return metadata_return_ty != TY_UNKNOWN && metadata_return_ty != INVALID
               ? metadata_return_ty
               : call_return_type[fn_token];
}

bool statement_position_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;
    uint context = hir_call_context_stmt_node[call_node];
    return valid_node(context) && hir_kind[context] == HIR_STMT;
}

bool print_call_node(uint call_node)
{
    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) &&
           statement_position_call(call_node) &&
           call_intrinsic_tag[callee_token] == INTRINSIC_TEXT_WRITE &&
           hir_call_arg_count[call_node] == 1u;
}

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return callee_node;

    callee_node = resolve_expr_node(callee_node);
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR
               ? callee_node
               : INVALID;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    if (!valid_node(member_node))
        return INVALID;
    uint receiver_node = hir_member_receiver_node[member_node];
    return valid_node(receiver_node) ? receiver_node : INVALID;
}

bool direct_call_has_receiver_arg(uint call_node, uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    uint receiver_node = method_receiver_node_for_call(call_node);
    if (!valid_node(receiver_node))
        return false;
    uint explicit_arg_count = hir_call_arg_count[call_node];
    return call_param_count[fn_token] == explicit_arg_count + 1u;
}

bool direct_user_call_node(
    uint call_node,
    out uint fn_token,
    out uint wasm_func_index,
    out uint arg_count)
{
    fn_token = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!supported_call_target_token(fn_token))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_has_receiver_arg(call_node, fn_token);
    arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT)
        return false;

    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint param_ty = call_param_type_value(fn_token, i);
        if (!type_is_i32_abi_param(fn_token, i, param_ty) && param_ty != TY_FLOAT)
            return false;
    }

    wasm_func_index = wasm_call_target_for_call(call_node, fn_token);
    return true;
}

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token) || language_symbol >= 63u)
        return false;
    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

uint host_param_type(uint fn_token, uint ordinal)
{
    return call_param_type_value(fn_token, ordinal);
}

bool host_i32_abi_param_type(uint ty)
{
    return ty == TY_INT || ty == TY_UINT || ty == TY_UNKNOWN;
}

bool host_i32_abi_return_type(uint ty)
{
    return ty == TY_INT || ty == TY_UINT || ty == TY_UNKNOWN;
}

bool host_stdout_write_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_STDOUT) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_STDOUT)))
        return false;

    uint param0 = host_param_type(fn_token, 0u);
    uint param1 = host_param_type(fn_token, 1u);
    bool param0_ok = host_i32_abi_param_type(param0);
    bool param1_ok = host_i32_abi_param_type(param1);
    return hir_call_arg_count[call_node] == 2u &&
           call_return_type_for_call(call_node, callee_token, fn_token) == TY_INT &&
           param0_ok &&
           param1_ok;
}

bool host_stdout_write_expr_and_len(uint call_node, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_stdout_write_call_node(call_node))
        return false;

    uint arg0_len = 0u;
    uint arg1_len = 0u;
    if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), arg0_len) ||
        !direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 1u), arg1_len))
    {
        return false;
    }

    len = arg0_len + arg1_len + 1u + u32_leb_len(WASM_WRITE_STDOUT_FUNC_INDEX);
    return true;
}

bool host_no_arg_i32_call_node(uint call_node, uint language_symbol)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    bool return_ok =
        host_i32_abi_return_type(call_return_type_for_call(call_node, callee_token, fn_token));
    return hir_call_arg_count[call_node] == 0u && return_ok;
}

bool host_no_arg_i32_expr_and_len(uint call_node, uint language_symbol, uint wasm_func_index, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_no_arg_i32_call_node(call_node, language_symbol))
        return false;

    len = 1u + wasm_call_index_len(wasm_func_index);
    return true;
}

bool host_i32_call_node(uint call_node, uint language_symbol, uint expected_arg_count)
{
    if (!valid_node(call_node) ||
        hir_kind[call_node] != HIR_CALL_EXPR)
    {
        return false;
    }

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    if (hir_call_arg_count[call_node] != expected_arg_count)
        return false;
    return true;
}

bool host_i32_call_expr_and_len(
    uint call_node,
    uint language_symbol,
    uint wasm_func_index,
    uint expected_arg_count,
    out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_i32_call_node(call_node, language_symbol, expected_arg_count))
        return false;

    len = 1u + wasm_call_index_len(wasm_func_index);
    for (uint i = 0u; i < expected_arg_count; i += 1u)
    {
        uint arg_len = 0u;
        if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, i), arg_len))
            return false;
        len += arg_len;
    }
    return true;
}

bool host_void_call_node(uint call_node, uint language_symbol, uint expected_arg_count)
{
    if (!valid_node(call_node) ||
        hir_kind[call_node] != HIR_CALL_EXPR)
    {
        return false;
    }

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    bool return_ok =
        call_return_type_for_call(call_node, callee_token, fn_token) == TY_VOID;
    if (hir_call_arg_count[call_node] != expected_arg_count || !return_ok)
        return false;

    for (uint i = 0u; i < expected_arg_count; i += 1u)
    {
        uint param = host_param_type(fn_token, i);
        if (!host_i32_abi_param_type(param))
            return false;
    }
    return true;
}

bool host_void_call_expr_and_len(
    uint call_node,
    uint language_symbol,
    uint wasm_func_index,
    uint expected_arg_count,
    out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_void_call_node(call_node, language_symbol, expected_arg_count))
        return false;

    len = 1u + wasm_call_index_len(wasm_func_index);
    for (uint i = 0u; i < expected_arg_count; i += 1u)
    {
        uint arg_len = 0u;
        if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, i), arg_len))
            return false;
        len += arg_len;
    }
    return true;
}

bool host_process_arg_len_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_ARG_LEN) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_ARG_LEN)))
    {
        return false;
    }

    return hir_call_arg_count[call_node] == 1u &&
           call_return_type_for_call(call_node, callee_token, fn_token) == TY_INT &&
           host_param_type(fn_token, 0u) == TY_INT;
}

bool host_process_arg_len_expr_and_len(uint call_node, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_process_arg_len_call_node(call_node))
        return false;

    uint arg0_len = 0u;
    if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), arg0_len))
        return false;

    len = arg0_len + 1u + u32_leb_len(WASM_PROCESS_ARG_LEN_FUNC_INDEX);
    return true;
}

bool host_process_arg_read_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_ARG_READ) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_ARG_READ)))
    {
        return false;
    }

    uint param1 = host_param_type(fn_token, 1u);
    uint param2 = host_param_type(fn_token, 2u);
    bool param1_ok = host_i32_abi_param_type(param1);
    bool param2_ok = host_i32_abi_param_type(param2);
    return hir_call_arg_count[call_node] == 3u &&
           call_return_type_for_call(call_node, callee_token, fn_token) == TY_INT &&
           host_param_type(fn_token, 0u) == TY_INT &&
           param1_ok &&
           param2_ok;
}

bool host_process_arg_read_expr_and_len(uint call_node, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_process_arg_read_call_node(call_node))
        return false;

    uint arg0_len = 0u;
    uint arg1_len = 0u;
    uint arg2_len = 0u;
    if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), arg0_len) ||
        !direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 1u), arg1_len) ||
        !direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 2u), arg2_len))
    {
        return false;
    }

    len = arg0_len + arg1_len + arg2_len + 1u + u32_leb_len(WASM_PROCESS_ARG_READ_FUNC_INDEX);
    return true;
}

bool i32_array_data_ptr_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR)))
    {
        return false;
    }

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    return hir_call_arg_count[call_node] == 1u &&
           (return_ty == TY_UINT || return_ty == TY_INT);
}

bool i32_array_data_ptr_expr_and_len(uint call_node, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!i32_array_data_ptr_call_node(call_node))
        return false;

    uint arg_len = 0u;
    if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), arg_len) ||
        arg_len == 0u)
    {
        return false;
    }

    len = arg_len;
    return true;
}

uint call_arg0_node(uint call_node)
{
    if (!print_call_node(call_node))
        return INVALID;

    uint arg = hir_call_arg_start[call_node];
    if (valid_node(arg) &&
        hir_call_arg_parent_call[arg] == call_node &&
        hir_call_arg_ordinal[arg] == 0u)
    {
        return arg;
    }
    return INVALID;
}

uint direct_call_arg_node(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= hir_call_arg_count[call_node])
        return INVALID;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    if (row >= active_hir_node_count())
        return INVALID;

    uint node = call_arg_row_node[row];
    return valid_node(node) ? node : INVALID;
}

uint direct_call_abi_arg_node(uint call_node, uint fn_token, uint ordinal)
{
    if (direct_call_has_receiver_arg(call_node, fn_token))
    {
        if (ordinal == 0u)
            return method_receiver_node_for_call(call_node);
        return direct_call_arg_node(call_node, ordinal - 1u);
    }
    return direct_call_arg_node(call_node, ordinal);
}

bool let_initializer_for_decl_token(uint decl_token, out uint init_expr)
{
    init_expr = INVALID;
    if (!valid_token(decl_token))
        return false;

    init_expr = body_let_init_expr_by_decl_token[decl_token];
    return valid_node(init_expr) && hir_kind[init_expr] == HIR_EXPR;
}

bool name_const_record_value(uint name_node, out uint value)
{
    value = 0u;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL)
        return false;
    value = record.y;
    return true;
}

bool name_let_initializer_expr(uint name_node, out uint init_expr)
{
    init_expr = INVALID;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    return let_initializer_for_decl_token(decl_token, init_expr);
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value = value >> 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint u32_leb_byte(uint value, uint byte_i)
{
    uint shift = byte_i * 7u;
    uint byte_value = (value >> shift) & 0x7fu;
    return (value >> (shift + 7u)) == 0u ? byte_value : (byte_value | 0x80u);
}

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint f32_const_byte(uint bits, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_F32_CONST;
    return (bits >> ((byte_i - 1u) * 8u)) & 0xffu;
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint memarg_load_byte(uint op, uint offset, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return u32_leb_byte(offset, byte_i - 2u);
}

uint memarg_len(uint offset)
{
    return 2u + u32_leb_len(offset);
}

bool local_decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;

    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        decl_token = local_index;
        return true;
    }

    uint init_expr = INVALID;
    if (let_initializer_for_decl_token(decl_token, init_expr))
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return false;
        decl_token = local_index;
        return true;
    }

    uint encoded_fn = enclosing_fn[decl_token];
    if (encoded_fn == 0u || encoded_fn - 1u != owner_fn ||
        !function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        return false;
    }
    decl_token = local_index;
    return true;
}

uint local_decl_fragment_len(uint let_count, uint let_max_token)
{
    if (let_count == 0u || !valid_token(let_max_token))
        return 1u;
    return local_decl_fragment_len_from_count(let_max_token + 1u);
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

bool expr_binary_op_supported(uint form)
{
    return form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

uint expr_binary_op_byte(uint form)
{
    if (form == HIR_EXPR_EQ) return WASM_I32_EQ;
    if (form == HIR_EXPR_NE) return WASM_I32_NE;
    if (form == HIR_EXPR_LT) return WASM_I32_LT_S;
    if (form == HIR_EXPR_GT) return WASM_I32_GT_S;
    if (form == HIR_EXPR_LE) return WASM_I32_LE_S;
    if (form == HIR_EXPR_GE) return WASM_I32_GE_S;
    if (form == HIR_EXPR_ADD) return WASM_I32_ADD;
    if (form == HIR_EXPR_SUB) return WASM_I32_SUB;
    if (form == HIR_EXPR_MUL) return WASM_I32_MUL;
    if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND) return WASM_I32_AND;
    if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR) return WASM_I32_OR;
    if (form == HIR_EXPR_BIT_XOR) return WASM_I32_XOR;
    if (form == HIR_EXPR_SHL) return WASM_I32_SHL;
    if (form == HIR_EXPR_SHR) return WASM_I32_SHR_S;
    if (form == HIR_EXPR_DIV) return WASM_I32_DIV_S;
    if (form == HIR_EXPR_MOD) return WASM_I32_REM_S;
    return 0u;
}

bool expr_contains_member(uint node)
{
    if (valid_node(node) && hir_kind[node] == HIR_MEMBER_EXPR)
        return valid_token(hir_member_name_token[node]);
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    return expr_subtree_features[node].y != 0u;
}

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT)
        return true;
    if (form == HIR_EXPR_NAME)
    {
        uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
        return visible_type_for_token(name_token) == TY_FLOAT;
    }
    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_name = hir_member_name_token[node];
        return visible_type_for_token(member_name) == TY_FLOAT;
    }
    return false;
}

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    return expr_form(node) == HIR_EXPR_NEG && expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

uint expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    if (expr_atom_is_f32(left) || expr_atom_is_f32(right))
    {
        if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
        if (form == HIR_EXPR_NE) return WASM_F32_NE;
        if (form == HIR_EXPR_LT) return WASM_F32_LT;
        if (form == HIR_EXPR_GT) return WASM_F32_GT;
        if (form == HIR_EXPR_LE) return WASM_F32_LE;
        if (form == HIR_EXPR_GE) return WASM_F32_GE;
        if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
        if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
        return 0u;
    }
    return expr_binary_op_byte(form);
}

uint memarg_i32_byte(uint op, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return 0u;
}

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint wasm_global_exclusive_prefix(
    uint item_i,
    uint workgroup_size,
    StructuredBuffer<uint> local_prefix,
    StructuredBuffer<uint> block_prefix)
{
    uint block_i = item_i / workgroup_size;
    uint prior_blocks = block_i == 0u ? 0u : block_prefix[block_i - 1u];
    return prior_blocks + local_prefix[item_i];
}

uint agg_local_base_slots(uint decl_token)
{
    return wasm_global_exclusive_prefix(
        decl_token,
        256u,
        wasm_agg_local_base_by_token,
        wasm_agg_local_block_prefix);
}

bool aggregate_lit_for_decl_token(uint decl_token, out uint lit_node)
{
    lit_node = INVALID;
    if (!valid_token(decl_token))
        return false;
    return wasm_agg_local_width_by_token[decl_token] != 0u;
}

bool aggregate_decl_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint lit_node = INVALID;
    return aggregate_lit_for_decl_token(decl_token, lit_node);
}

bool aggregate_name_address_expr_plan(
    uint node,
    out uint opcode,
    out uint operand,
    out uint len)
{
    opcode = 0u;
    operand = 0u;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    bool is_param = function_param_local_index(decl_token, owner_fn, local_index);
    if (!is_param && valid_token(owner_fn))
    {
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
        if (ordinal != INVALID)
        {
            local_index = function_param_abi_ordinal(owner_fn, ordinal);
            is_param = true;
        }
    }
    if (is_param)
    {
        uint decl_ty = visible_type_for_token(decl_token);
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
        uint param_ty = call_param_type_value(owner_fn, ordinal);
        if (decl_ty != TY_UNKNOWN &&
            decl_ty < TY_ARRAY_BASE &&
            param_ty < TY_ARRAY_BASE &&
            method_decl_param_offset[owner_fn] != decl_token)
        {
            return false;
        }
        opcode = WASM_LOCAL_GET;
        operand = local_index;
        len = local_get_len(local_index);
        return true;
    }

    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        opcode = WASM_I32_CONST;
        operand = base_address;
        len = 1u + i32_sleb_len(base_address);
        return true;
    }

    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
    {
        if (!function_non_param_local_index_for_type(decl_token, owner_fn, TY_INT, local_index))
            return false;
        opcode = WASM_LOCAL_GET;
        operand = local_index;
        len = local_get_len(local_index);
        return true;
    }

    return false;
}

bool aggregate_name_address_expr_and_len(uint node, out uint len)
{
    uint opcode = 0u;
    uint operand = 0u;
    return aggregate_name_address_expr_plan(node, opcode, operand, len);
}

uint aggregate_name_address_expr_byte(uint node, uint byte_i)
{
    uint opcode = 0u;
    uint operand = 0u;
    uint len = 0u;
    if (!aggregate_name_address_expr_plan(node, opcode, operand, len))
        return 0u;
    return opcode == WASM_LOCAL_GET
               ? local_get_byte(operand, byte_i)
               : i32_const_byte(operand, byte_i);
}

bool aggregate_address_expr_and_len(uint node, out uint len)
{
    len = 0u;
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_MEMBER_EXPR && expr_form(node) != HIR_EXPR_NAME))
    {
        node = resolve_expr_node(node);
    }
    if (!valid_node(node))
        return false;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_name = hir_member_name_token[node];
        if (!valid_token(member_name) || visible_type_for_token(member_name) < TY_ARRAY_BASE)
            return false;
    }
    else
    {
        uint name_len = 0u;
        if (!aggregate_name_address_expr_and_len(node, name_len))
            return false;
    }
    uint2 total = expr_subtree_total[node];
    if (total.y != 0u || total.x == 0u)
        return false;
    len = total.x;
    return true;
}

bool aggregate_member_address_and_len(uint node, out uint address, out uint len)
{
    address = 0u;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return false;

    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return false;

    uint field_index = member_result_field_index[member_name];
    if (field_index == INVALID)
        return false;

    uint2 total = expr_subtree_total[node];
    if (total.y != 0u || total.x == 0u)
        return false;

    address = 0u;
    len = total.x;
    return true;
}

bool expr_non_call_atom_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint decl_token = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, decl_token))
    {
        len = local_get_len(decl_token);
        return true;
    }
    uint address = 0u;
    if (aggregate_member_address_and_len(node, address, len))
        return true;

    uint value = 0u;
    if (form == HIR_EXPR_INT ||
        form == HIR_EXPR_TRUE ||
        form == HIR_EXPR_FALSE ||
        (form == HIR_EXPR_NAME && name_const_record_value(node, value)))
    {
        if (form == HIR_EXPR_INT)
            value = hir_expr_int_value[node];
        else if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
            value = form == HIR_EXPR_TRUE ? 1u : 0u;
        len = 1u + i32_sleb_len(value);
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
        return true;
    }
    return false;
}

bool const_atom_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return form == HIR_EXPR_NAME && name_const_record_value(node, value);
}

bool unary_const_value(uint form, uint inner, out uint value)
{
    if (form == HIR_EXPR_NEG)
    {
        value = 0u - inner;
        return true;
    }
    if (form == HIR_EXPR_NOT)
    {
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    value = 0u;
    return false;
}

bool direct_call_arg_const_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    if (const_atom_value(node, value))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint inner = 0u;
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), inner) &&
            !const_atom_value(expr_record_slot(node, EXPR_RECORD_RIGHT), inner))
        {
            return false;
        }
        return unary_const_value(form, inner, value);
    }

    if (form == HIR_EXPR_SUB)
    {
        uint left = 0u;
        uint right = 0u;
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), left) ||
            !const_atom_value(expr_record_slot(node, EXPR_RECORD_RIGHT), right))
        {
            return false;
        }
        value = uint(int(left) - int(right));
        return true;
    }

    return false;
}

bool expr_tree_and_len(uint root_node, out uint len)
{
    len = 0u;
    uint root = resolve_expr_node(root_node);
    if (!valid_node(root))
        return false;
    uint2 total = expr_subtree_total[root];
    uint2 features = expr_subtree_features[root];
    len = total.x;
    return total.y == 0u && features.x == 0u && len != 0u;
}

bool direct_call_arg_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint2 total = expr_subtree_total[node];
    len = total.x;
    return total.y == 0u && len != 0u;
}

bool direct_call_arg_abi_expr_and_len(uint node, uint param_ty, out uint len)
{
    if (param_ty == TY_STRING)
        return host_string_value_expr_and_len(node, len);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_and_len(node, len);
    return direct_call_arg_expr_and_len(node, len);
}

bool direct_call_arg_scalar_and_len(uint node, out uint len)
{
    return direct_call_arg_expr_and_len(node, len);
}

uint source_data_base()
{
    return (gParams.n_tokens + 1u) * 4u;
}

bool string_literal_ptr_len(uint node, out uint ptr, out uint len)
{
    ptr = 0u;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_STRING)
        return false;

    uint start = hir_expr_string_start[node];
    uint raw_len = hir_expr_string_len[node];
    if (start == INVALID || start > gParams.source_len || raw_len > gParams.source_len - start)
        return false;

    ptr = source_data_base() + start;
    len = raw_len;
    return true;
}

bool string_value_expr_and_len(uint node, out uint len)
{
    len = 0u;
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
    {
        len = 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(str_len);
        return true;
    }

    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID;
    uint len_local = INVALID;
    if (!valid_token(decl_token) ||
        visible_type_for_token(decl_token) != TY_STRING ||
        !function_decl_local_index(decl_token, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return false;
    }

    len = local_get_len(ptr_local) + local_get_len(len_local);
    return true;
}

bool host_string_value_expr_and_len(uint node, out uint len)
{
    len = 0u;
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
    {
        len = 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(str_len);
        return true;
    }

    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(decl_token) ||
        !valid_token(owner_fn) ||
        visible_type_for_token(decl_token) != TY_STRING)
    {
        return false;
    }

    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[owner_fn])
    {
        uint ptr_local = function_param_abi_ordinal(owner_fn, ordinal);
        if (ptr_local == INVALID)
            return false;
        len = local_get_len(ptr_local) + local_get_len(ptr_local + 1u);
        return true;
    }

    uint local_count = local_decl_count_for_function_token(owner_fn);
    uint ptr_local = function_param_abi_count(owner_fn) + decl_token;
    uint len_local = function_param_abi_count(owner_fn) + local_count + decl_token;
    len = local_get_len(ptr_local) + local_get_len(len_local);
    return true;
}

uint string_value_expr_byte(uint node, uint byte_i)
{
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
    {
        uint ptr_len = 1u + i32_sleb_len(ptr);
        if (byte_i < ptr_len)
            return i32_const_byte(ptr, byte_i);
        return i32_const_byte(str_len, byte_i - ptr_len);
    }

    node = resolve_expr_node(node);
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID;
    uint len_local = INVALID;
    if (!function_decl_local_index(decl_token, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return 0u;
    }

    uint ptr_len = local_get_len(ptr_local);
    if (byte_i < ptr_len)
        return local_get_byte(ptr_local, byte_i);
    return local_get_byte(len_local, byte_i - ptr_len);
}

bool host_string_i32_call_node(
    uint call_node,
    uint language_symbol,
    uint expected_arg_count)
{
    if (!valid_node(call_node) ||
        hir_kind[call_node] != HIR_CALL_EXPR)
    {
        return false;
    }

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    bool return_ok = return_ty == TY_INT || return_ty == TY_UINT;
    return hir_call_arg_count[call_node] == expected_arg_count &&
           return_ok;
}

bool host_string_i32_call_expr_and_len(
    uint call_node,
    uint language_symbol,
    uint wasm_func_index,
    uint mode,
    out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);

    if (mode == HOST_STR_CALL_OPEN_READ_PATH || mode == HOST_STR_CALL_OPEN_WRITE_PATH)
    {
        if (!host_string_i32_call_node(call_node, language_symbol, 1u))
            return false;
        uint string_len = 0u;
        if (!host_string_value_expr_and_len(direct_call_arg_node(call_node, 0u), string_len))
            return false;
        len = string_len + 1u + wasm_call_index_len(wasm_func_index);
        return true;
    }

    if (mode == HOST_STR_CALL_WRITE_TEXT)
    {
        if (!host_string_i32_call_node(call_node, language_symbol, 2u))
            return false;
        uint handle_len = 0u;
        uint string_len = 0u;
        if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), handle_len) ||
            !host_string_value_expr_and_len(direct_call_arg_node(call_node, 1u), string_len))
        {
            return false;
        }
        len = handle_len + string_len + 1u + wasm_call_index_len(wasm_func_index);
        return true;
    }

    return false;
}

bool host_string_i32_expr_and_len(uint node, out uint len)
{
    if (host_string_i32_call_expr_and_len(
            node,
            LANGUAGE_SYMBOL_OPEN_READ_PATH,
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_READ_PATH,
            len))
        return true;
    if (host_string_i32_call_expr_and_len(
            node,
            LANGUAGE_SYMBOL_OPEN_WRITE_PATH,
            WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_WRITE_PATH,
            len))
        return true;
    return host_string_i32_call_expr_and_len(
        node,
        LANGUAGE_SYMBOL_WRITE_TEXT,
        WASM_STD_WRITE_TEXT_FUNC_INDEX,
        HOST_STR_CALL_WRITE_TEXT,
        len);
}

bool direct_call_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return false;

    uint2 total = expr_subtree_total[node];
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    if (total.y != 0u || total.x < tail_len)
        return false;
    len = total.x;
    return true;
}

bool direct_call_simple_args_expr_and_len(uint node, out uint len)
{
    return direct_call_expr_and_len(node, len);
}

bool expr_atom_and_len(uint node, out uint len)
{
    return expr_non_call_atom_and_len(node, len);
}

bool binary_direct_call_expr_record(
    uint node,
    out uint call_node,
    out uint atom_node,
    out uint op,
    out uint call_side,
    out uint len)
{
    call_node = INVALID;
    atom_node = INVALID;
    op = 0u;
    call_side = 0u;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || !expr_binary_op_supported(expr_form(node)))
        return false;
    op = expr_binary_op_byte(expr_form(node));
    if (op == 0u)
        return false;

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_expr_len = 0u;
    uint right_expr_len = 0u;
    uint left_call_len = 0u;
    uint right_call_len = 0u;
    bool left_expr = expr_non_call_atom_and_len(left, left_expr_len);
    bool right_expr = expr_non_call_atom_and_len(right, right_expr_len);
    bool left_call = direct_call_simple_args_expr_and_len(left, left_call_len);
    bool right_call = direct_call_simple_args_expr_and_len(right, right_call_len);

    if (left_expr && right_call)
    {
        call_node = resolve_expr_node(right);
        atom_node = left;
        call_side = 1u;
        len = left_expr_len + right_call_len + 1u;
        return true;
    }
    if (left_call && right_expr)
    {
        call_node = resolve_expr_node(left);
        atom_node = right;
        call_side = 0u;
        len = left_call_len + right_expr_len + 1u;
        return true;
    }
    return false;
}

bool binary_direct_call_expr_and_len(uint node, out uint len)
{
    uint call_node = INVALID;
    uint atom_node = INVALID;
    uint op = 0u;
    uint call_side = 0u;
    return binary_direct_call_expr_record(node, call_node, atom_node, op, call_side, len);
}

bool expr_simple_and_len(uint node, out uint len)
{
    return expr_tree_and_len(node, len);
}

bool assign_op_supported(uint op)
{
    return op == ASSIGN_OP_SET ||
           op == ASSIGN_OP_ADD ||
           op == ASSIGN_OP_SUB ||
           op == ASSIGN_OP_MUL ||
           op == ASSIGN_OP_DIV ||
           op == ASSIGN_OP_MOD;
}

uint assign_op_byte(uint op)
{
    if (op == ASSIGN_OP_ADD) return WASM_I32_ADD;
    if (op == ASSIGN_OP_SUB) return WASM_I32_SUB;
    if (op == ASSIGN_OP_MUL) return WASM_I32_MUL;
    if (op == ASSIGN_OP_DIV) return WASM_I32_DIV_S;
    if (op == ASSIGN_OP_MOD) return WASM_I32_REM_S;
    return 0u;
}

bool supported_let_expr_fragment(
    uint node,
    out uint decl_token,
    out uint expr_node,
    out uint len)
{
    decl_token = INVALID;
    expr_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    expr_node = stmt_record_slot(node, 2u);
    uint expr_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(expr_node) ||
        !expr_simple_and_len(expr_node, expr_len))
    {
        return false;
    }

    uint local_index = INVALID;
    uint local_ty = local_decl_initializer_expr_type(expr_node);
    if (local_ty == TY_UNKNOWN)
        local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;
    if (!function_non_param_local_index_for_type(
            decl_token,
            node_enclosing_fn_token(node),
            local_ty,
            local_index))
        return false;
    decl_token = local_index;
    len = expr_len + local_set_len(local_index);
    return true;
}

bool supported_let_binary_direct_call_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint expr_node,
    out uint op,
    out uint call_side,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    expr_node = INVALID;
    op = 0u;
    call_side = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    uint init_expr = stmt_record_slot(node, 2u);
    uint expr_len = 0u;
    if (!valid_node(init_expr) ||
        !binary_direct_call_expr_record(init_expr, call_node, expr_node, op, call_side, expr_len))
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = local_decl_initializer_expr_type(init_expr);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;

    uint local_index = INVALID;
    if (!valid_token(decl_token) ||
        !function_non_param_local_index_for_type(
            decl_token,
            node_enclosing_fn_token(node),
            local_ty,
            local_index))
    {
        return false;
    }

    decl_token = local_index;
    len = expr_len + local_set_len(local_index);
    return true;
}

bool supported_let_direct_call_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !direct_call_expr_and_len(call_node, call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;
    if (!function_non_param_local_index_for_type(
            decl_token,
            node_enclosing_fn_token(node),
            local_ty,
            local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_stdout_write_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_stdout_write_expr_and_len(call_node, call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_process_argc_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_no_arg_i32_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_ARGC,
            WASM_PROCESS_ARGC_FUNC_INDEX,
            call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_secure_u32_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_no_arg_i32_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_SECURE_U32,
            WASM_RANDOM_SECURE_U32_FUNC_INDEX,
            call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_unix_seconds_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_no_arg_i32_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_UNIX_SECONDS,
            WASM_TIME_UNIX_SECONDS_FUNC_INDEX,
            call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_i32_call_fragment(
    uint node,
    uint language_symbol,
    uint wasm_func_index,
    uint arg_count,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_i32_call_expr_and_len(
            call_node,
            language_symbol,
            wasm_func_index,
            arg_count,
            call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_file_stdio_host_i32_call_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint wasm_func_index,
    out uint arg_count,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    len = 0u;

    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_READ_I32,
            WASM_STD_READ_I32_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STD_READ_I32_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_WRITE_I32,
            WASM_STD_WRITE_I32_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STD_WRITE_I32_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_WRITE_BYTE,
            WASM_STD_WRITE_BYTE_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STD_WRITE_BYTE_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_WRITE_NEWLINE,
            WASM_STD_WRITE_NEWLINE_FUNC_INDEX,
            1u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STD_WRITE_NEWLINE_FUNC_INDEX;
        arg_count = 1u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_CLOSE_FILE,
            WASM_FS_CLOSE_FUNC_INDEX,
            1u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_CLOSE_FUNC_INDEX;
        arg_count = 1u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_CLOSE,
            WASM_FS_CLOSE_FUNC_INDEX,
            1u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_CLOSE_FUNC_INDEX;
        arg_count = 1u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_READ,
            WASM_FS_READ_FUNC_INDEX,
            3u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_READ_FUNC_INDEX;
        arg_count = 3u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_WRITE,
            WASM_FS_WRITE_FUNC_INDEX,
            3u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_WRITE_FUNC_INDEX;
        arg_count = 3u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_OPEN_READ,
            WASM_FS_OPEN_READ_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_OPEN_READ_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_OPEN_WRITE,
            WASM_FS_OPEN_WRITE_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_OPEN_WRITE_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_OPEN_APPEND,
            WASM_FS_OPEN_APPEND_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_OPEN_APPEND_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_WRITE_STDERR,
            WASM_STDIO_WRITE_STDERR_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STDIO_WRITE_STDERR_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_READ_STDIN,
            WASM_STDIO_READ_STDIN_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_STDIO_READ_STDIN_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_FILL_SECURE_BYTES,
            WASM_RANDOM_FILL_SECURE_BYTES_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_RANDOM_FILL_SECURE_BYTES_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_REMOVE_FILE,
            WASM_FS_REMOVE_FILE_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_REMOVE_FILE_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_CREATE_DIR,
            WASM_FS_CREATE_DIR_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_CREATE_DIR_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_REMOVE_DIR,
            WASM_FS_REMOVE_DIR_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_REMOVE_DIR_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_RENAME,
            WASM_FS_RENAME_FUNC_INDEX,
            4u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_FS_RENAME_FUNC_INDEX;
        arg_count = 4u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_MONOTONIC_READ,
            WASM_TIME_MONOTONIC_READ_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_TIME_MONOTONIC_READ_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_SYSTEM_READ,
            WASM_TIME_SYSTEM_READ_FUNC_INDEX,
            2u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_TIME_SYSTEM_READ_FUNC_INDEX;
        arg_count = 2u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_SLEEP_MS_I32,
            WASM_TIME_SLEEP_MS_I32_FUNC_INDEX,
            1u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_TIME_SLEEP_MS_I32_FUNC_INDEX;
        arg_count = 1u;
        return true;
    }
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_REALLOC,
            WASM_REALLOC_FUNC_INDEX,
            4u,
            decl_token,
            call_node,
            len))
    {
        wasm_func_index = WASM_REALLOC_FUNC_INDEX;
        arg_count = 4u;
        return true;
    }
    return false;
}

bool supported_let_host_string_call_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint wasm_func_index,
    out uint mode,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    wasm_func_index = INVALID;
    mode = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    if (!valid_token(decl_token) || !valid_node(call_node))
        return false;

    uint call_len = 0u;
    if (host_string_i32_call_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_OPEN_READ_PATH,
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_READ_PATH,
            call_len))
    {
        wasm_func_index = WASM_STD_OPEN_READ_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_READ_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_OPEN_WRITE_PATH,
                 WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
                 HOST_STR_CALL_OPEN_WRITE_PATH,
                 call_len))
    {
        wasm_func_index = WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_WRITE_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_WRITE_TEXT,
                 WASM_STD_WRITE_TEXT_FUNC_INDEX,
                 HOST_STR_CALL_WRITE_TEXT,
                 call_len))
    {
        wasm_func_index = WASM_STD_WRITE_TEXT_FUNC_INDEX;
        mode = HOST_STR_CALL_WRITE_TEXT;
    }
    else
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_host_void_call_fragment(
    uint node,
    uint language_symbol,
    uint wasm_func_index,
    uint arg_count,
    out uint call_node,
    out uint len)
{
    call_node = INVALID;
    len = 0u;
    if (!statement_position_call(node))
        return false;

    call_node = node;
    return host_void_call_expr_and_len(
        call_node,
        language_symbol,
        wasm_func_index,
        arg_count,
        len);
}

bool supported_let_host_process_arg_len_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_process_arg_len_expr_and_len(call_node, call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_host_process_arg_read_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !host_process_arg_read_expr_and_len(call_node, call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_let_i32_array_data_ptr_fragment(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint len)
{
    decl_token = INVALID;
    call_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    call_node = stmt_record_slot(node, 2u);
    uint call_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(call_node) ||
        !i32_array_data_ptr_expr_and_len(call_node, call_len))
    {
        return false;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = call_len + local_set_len(local_index);
    return true;
}

bool supported_assign_expr_fragment(
    uint node,
    out uint target_decl,
    out uint rhs_node,
    out uint op,
    out uint len)
{
    target_decl = INVALID;
    rhs_node = INVALID;
    op = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return false;
    }

    uint target = stmt_record_slot(node, 1u);
    rhs_node = stmt_record_slot(node, 2u);
    op = stmt_record_slot(node, 3u);
    uint rhs_len = 0u;
    if (!assign_op_supported(op) ||
        !local_decl_token_for_name_expr(target, target_decl) ||
        !expr_simple_and_len(rhs_node, rhs_len))
    {
        return false;
    }

    len = op == ASSIGN_OP_SET
              ? rhs_len + local_set_len(target_decl)
              : local_get_len(target_decl) + rhs_len + 1u + local_set_len(target_decl);
    return true;
}

bool supported_assign_direct_call_fragment(
    uint node,
    out uint target_decl,
    out uint rhs_node,
    out uint op,
    out uint len)
{
    target_decl = INVALID;
    rhs_node = INVALID;
    op = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return false;
    }

    uint target = stmt_record_slot(node, 1u);
    rhs_node = resolve_expr_node(stmt_record_slot(node, 2u));
    op = stmt_record_slot(node, 3u);
    uint rhs_len = 0u;
    if (!assign_op_supported(op) ||
        !local_decl_token_for_name_expr(target, target_decl) ||
        !direct_call_expr_and_len(rhs_node, rhs_len))
    {
        return false;
    }

    len = op == ASSIGN_OP_SET
              ? rhs_len + local_set_len(target_decl)
              : local_get_len(target_decl) + rhs_len + 1u + local_set_len(target_decl);
    return true;
}

bool print_call_expr_and_len(uint call_node, out uint expr_node, out uint len)
{
    expr_node = INVALID;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    uint expr_len = 0u;
    if (!valid_node(arg_node) || !expr_simple_and_len(arg_node, expr_len))
        return false;

    expr_node = arg_node;
    len = expr_len + 1u + 2u;
    return true;
}

bool print_call_direct_call_and_len(uint call_node, out uint expr_node, out uint len)
{
    expr_node = INVALID;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    uint expr_len = 0u;
    if (!valid_node(arg_node) || !direct_call_expr_and_len(arg_node, expr_len))
        return false;

    expr_node = arg_node;
    len = expr_len + 1u + 2u;
    return true;
}

bool print_call_local_and_len(uint call_node, out uint decl_token, out uint len)
{
    decl_token = INVALID;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    if (!valid_node(arg_node) || !local_decl_token_for_name_expr(arg_node, decl_token))
        return false;

    len = local_get_len(decl_token) + 1u + 2u;
    return true;
}

bool return_expr_local_and_len(uint return_node, out uint decl_token, out uint len)
{
    decl_token = INVALID;
    len = 0u;
    uint expr = stmt_record_slot(return_node, 1u);
    if (!valid_node(expr) || !local_decl_token_for_name_expr(expr, decl_token))
        return false;

    len = local_get_len(decl_token) + 1u;
    return true;
}

bool return_expr_fragment_and_len(uint return_node, out uint expr_node, out uint len)
{
    expr_node = INVALID;
    len = 0u;
    uint expr = resolve_expr_node(stmt_record_slot(return_node, 1u));
    if (!valid_node(expr))
        return false;

    uint2 total = expr_subtree_total[expr];
    if (total.y != 0u || total.x == 0u)
        return false;

    expr_node = expr;
    len = total.x + 1u;
    return true;
}

bool return_direct_call_fragment_and_len(uint return_node, out uint expr_node, out uint len)
{
    expr_node = INVALID;
    len = 0u;
    uint expr = stmt_record_slot(return_node, 1u);
    uint expr_len = 0u;
    if (!valid_node(expr) || !direct_call_expr_and_len(expr, expr_len))
        return false;

    expr_node = expr;
    len = expr_len + 1u;
    return true;
}

bool return_binary_direct_call_fragment_and_len(
    uint return_node,
    out uint call_node,
    out uint atom_node,
    out uint op,
    out uint call_side,
    out uint len)
{
    call_node = INVALID;
    atom_node = INVALID;
    op = 0u;
    call_side = 0u;
    len = 0u;
    uint expr = stmt_record_slot(return_node, 1u);
    uint expr_len = 0u;
    if (!valid_node(expr) ||
        !binary_direct_call_expr_record(expr, call_node, atom_node, op, call_side, expr_len))
    {
        return false;
    }

    len = expr_len + 1u;
    return true;
}

bool while_open_fragment_and_len(uint while_node, out uint condition_node, out uint len)
{
    condition_node = INVALID;
    len = 0u;
    if (!valid_node(while_node) ||
        hir_kind[while_node] != HIR_WHILE_STMT ||
        stmt_record_slot(while_node, 0u) != STMT_RECORD_KIND_WHILE)
    {
        return false;
    }

    condition_node = stmt_record_slot(while_node, 1u);
    uint condition_len = 0u;
    if (!valid_node(condition_node) || !expr_simple_and_len(condition_node, condition_len))
        return false;

    len = condition_len + 7u;
    return true;
}

bool while_close_token_and_len(uint while_node, out uint close_token, out uint len)
{
    close_token = INVALID;
    len = 0u;
    if (!valid_node(while_node) ||
        hir_kind[while_node] != HIR_WHILE_STMT ||
        stmt_record_slot(while_node, 0u) != STMT_RECORD_KIND_WHILE)
    {
        return false;
    }

    uint body = stmt_record_slot(while_node, 2u);
    if (!valid_node(body))
        return false;

    uint end = hir_token_end[body];
    if (end == 0u || end == INVALID)
        return false;

    close_token = end - 1u;
    if (!valid_token(close_token))
        return false;

    len = 4u;
    return true;
}

bool while_close_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;
    return_token = wasm_func_return_token_by_token[owner_fn];

    uint close_token = INVALID;
    uint len = 0u;
    if (!while_close_token_and_len(node, close_token, len))
        return false;

    token_i = close_token;
    fragment_len = len;
    fragment_meta = uint4(BODY_FRAGMENT_WHILE_CLOSE, 0u, 0u, close_token);
    return true;
}

bool if_open_fragment_and_len(uint if_node, out uint condition_node, out uint len)
{
    condition_node = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    condition_node = stmt_record_slot(if_node, 1u);
    uint then_block = stmt_record_slot(if_node, 2u);
    uint condition_len = 0u;
    if (!valid_node(condition_node) ||
        !valid_node(then_block) ||
        !expr_simple_and_len(condition_node, condition_len))
    {
        return false;
    }

    len = condition_len + 2u;
    return true;
}

bool block_close_token(uint block_node, out uint close_token)
{
    close_token = INVALID;
    if (!valid_node(block_node))
        return false;

    uint end = hir_token_end[block_node];
    if (end == 0u || end == INVALID)
        return false;

    close_token = end - 1u;
    return valid_token(close_token);
}

bool if_else_token_and_len(uint if_node, out uint else_token, out uint len)
{
    else_token = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    if (!valid_node(else_block) || !block_close_token(then_block, else_token))
        return false;

    len = 1u;
    return true;
}

bool if_end_token_and_len(uint if_node, out uint end_token, out uint len)
{
    end_token = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    uint close_block = valid_node(else_block) ? else_block : then_block;
    if (!block_close_token(close_block, end_token))
        return false;

    len = 1u;
    return true;
}

bool if_else_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;
    return_token = wasm_func_return_token_by_token[owner_fn];

    uint else_token = INVALID;
    uint len = 0u;
    if (!if_else_token_and_len(node, else_token, len))
        return false;

    token_i = else_token;
    fragment_len = len;
    fragment_meta = uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token);
    return true;
}

bool if_end_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;
    return_token = wasm_func_return_token_by_token[owner_fn];

    uint end_token = INVALID;
    uint len = 0u;
    if (!if_end_token_and_len(node, end_token, len))
        return false;

    token_i = end_token;
    fragment_len = len;
    fragment_meta = uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token);
    return true;
}

bool numeric_range_iterable_for_for_node(
    uint node,
    out uint binding_token,
    out uint range_node,
    out uint start_node,
    out uint end_node,
    out uint end_local_token)
{
    binding_token = INVALID;
    range_node = INVALID;
    start_node = INVALID;
    end_node = INVALID;
    end_local_token = INVALID;
    if (!valid_node(node) ||
        !((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
          stmt_record_slot(node, 0u) == STMT_RECORD_KIND_FOR))
    {
        return false;
    }

    binding_token = stmt_record_slot(node, 1u);
    range_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_token(binding_token) ||
        !valid_node(range_node) ||
        hir_kind[range_node] != HIR_EXPR ||
        expr_form(range_node) != HIR_EXPR_RANGE)
    {
        return false;
    }

    start_node = expr_record_slot(range_node, EXPR_RECORD_LEFT);
    end_node = expr_record_slot(range_node, EXPR_RECORD_RIGHT);
    end_local_token = hir_token_end[range_node];
    return valid_node(start_node) &&
           valid_node(end_node) &&
           valid_token(end_local_token);
}

bool for_open_range_fragment_and_len(
    uint node,
    out uint binding_token,
    out uint range_node,
    out uint end_local_token,
    out uint len)
{
    binding_token = INVALID;
    range_node = INVALID;
    end_local_token = INVALID;
    len = 0u;
    uint start_node = INVALID;
    uint end_node = INVALID;
    if (!numeric_range_iterable_for_for_node(
            node,
            binding_token,
            range_node,
            start_node,
            end_node,
            end_local_token))
    {
        return false;
    }

    uint body_node = stmt_record_slot(node, 3u);
    uint start_len = 0u;
    uint end_len = 0u;
    if (!valid_node(body_node) ||
        !expr_simple_and_len(start_node, start_len) ||
        !expr_simple_and_len(end_node, end_len))
    {
        return false;
    }

    len = start_len +
          local_set_len(call_param_count[node_enclosing_fn_token(node)] + binding_token) +
          end_len +
          local_set_len(call_param_count[node_enclosing_fn_token(node)] + end_local_token) +
          4u +
          local_get_len(call_param_count[node_enclosing_fn_token(node)] + binding_token) +
          local_get_len(call_param_count[node_enclosing_fn_token(node)] + end_local_token) +
          5u;
    uint binding_local = INVALID;
    uint end_local = INVALID;
    if (!function_non_param_local_index(binding_token, node_enclosing_fn_token(node), binding_local) ||
        !function_non_param_local_index(end_local_token, node_enclosing_fn_token(node), end_local))
    {
        return false;
    }
    binding_token = binding_local;
    end_local_token = end_local;
    return true;
}

bool for_close_token_and_len(uint node, out uint close_token, out uint len)
{
    close_token = INVALID;
    len = 0u;
    uint binding_token = INVALID;
    uint range_node = INVALID;
    uint start_node = INVALID;
    uint end_node = INVALID;
    uint end_local_token = INVALID;
    if (!numeric_range_iterable_for_for_node(
            node,
            binding_token,
            range_node,
            start_node,
            end_node,
            end_local_token))
    {
        return false;
    }

    uint body = stmt_record_slot(node, 3u);
    if (!valid_node(body))
        return false;

    uint end = hir_token_end[body];
    if (end == 0u || end == INVALID)
        return false;

    close_token = end - 1u;
    if (!valid_token(close_token))
        return false;

    uint binding_local = INVALID;
    if (!function_non_param_local_index(binding_token, node_enclosing_fn_token(node), binding_local))
        return false;

    len = local_get_len(binding_local) + local_set_len(binding_local) + 8u;
    return true;
}

bool for_close_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;
    return_token = wasm_func_return_token_by_token[owner_fn];

    uint close_token = INVALID;
    uint len = 0u;
    if (!for_close_token_and_len(node, close_token, len))
        return false;
    uint binding_local = INVALID;
    if (!function_non_param_local_index(
            stmt_record_slot(node, 1u),
            node_enclosing_fn_token(node),
            binding_local))
    {
        return false;
    }

    token_i = close_token;
    fragment_len = len;
    fragment_meta = uint4(
        BODY_FRAGMENT_FOR_CLOSE_RANGE_I32,
        binding_local,
        fragment_len,
        close_token);
    return true;
}
