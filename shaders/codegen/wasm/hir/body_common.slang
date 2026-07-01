// Shared helpers for the small HIR-driven WASM body pipeline.
//
// This handles the scalar entrypoint slice the module wrapper supports. Other
// shapes continue to fail closed with the stable WASM backend boundary. Body
// emission uses per-node fragment records followed by prefix-scan/scatter
// passes.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
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
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_array_lit_first_element;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_array_element_next;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
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
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> hir_nearest_loop_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;

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
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint LANGUAGE_SYMBOL_SECURE_U32 = 30u;
static const uint LANGUAGE_SYMBOL_ARGC = 33u;
static const uint LANGUAGE_SYMBOL_ARG_LEN = 34u;
static const uint LANGUAGE_SYMBOL_ARG_READ = 35u;
static const uint LANGUAGE_SYMBOL_UNIX_SECONDS = 36u;
static const uint LANGUAGE_SYMBOL_WRITE_STDOUT = 49u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;

static const uint ENTRYPOINT_MAIN = 1u;
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
static const uint HIR_NAME_EXPR = 22u;
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

static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_WRITE_STDOUT_FUNC_INDEX = 1u;
static const uint WASM_PROCESS_ARGC_FUNC_INDEX = 2u;
static const uint WASM_PROCESS_ARG_LEN_FUNC_INDEX = 3u;
static const uint WASM_PROCESS_ARG_READ_FUNC_INDEX = 4u;
static const uint WASM_RANDOM_SECURE_U32_FUNC_INDEX = 5u;
static const uint WASM_TIME_UNIX_SECONDS_FUNC_INDEX = 6u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 7u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
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
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_REM_S = 0x6fu;
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
static const uint MAX_CONST_EVAL_STACK = 16u;
static const uint MAX_CONST_EVAL_STEPS = 48u;
static const uint MAX_CONTROL_BRANCH_DEPTH = 16u;
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

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal >= WASM_MAX_DIRECT_CALL_ARGS)
        return TY_UNKNOWN;
    return row_major_load<uint>(
        call_param_type,
        fn_token,
        WASM_MAX_DIRECT_CALL_ARGS,
        ordinal,
        TY_UNKNOWN);
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

uint local_decl_fragment_len_from_count(uint local_count)
{
    if (local_count == 0u)
        return 1u;
    return 1u + u32_leb_len(local_count) + 1u;
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

    local_index = ordinal;
    return true;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint param_count = call_param_count[fn_token];
    if (param_count > WASM_MAX_DIRECT_CALL_ARGS)
        return false;

    local_index = param_count + decl_token;
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

    uint path_i = path_id_by_owner_hir[path_node];
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
    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
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

    fn_token = call_fn_index[callee_token];
    if (!supported_function_token(fn_token))
        return false;

    arg_count = hir_call_arg_count[call_node];
    if (arg_count > WASM_MAX_DIRECT_CALL_ARGS || call_param_count[fn_token] != arg_count)
        return false;

    if (call_return_type[callee_token] != TY_INT && call_return_type[fn_token] != TY_INT)
        return false;

    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i < arg_count && call_param_type_value(fn_token, i) != TY_INT)
            return false;
    }

    wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    return true;
}

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token) || language_symbol >= 53u)
        return false;
    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

uint host_param_type(uint fn_token, uint ordinal)
{
    return row_major_load<uint>(
        call_param_type,
        fn_token,
        WASM_MAX_DIRECT_CALL_ARGS,
        ordinal,
        TY_UNKNOWN);
}

bool host_stdout_write_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_STDOUT) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_STDOUT)))
        return false;

    uint param0 = host_param_type(fn_token, 0u);
    uint param1 = host_param_type(fn_token, 1u);
    bool param0_ok = param0 == TY_UINT || param0 == TY_INT;
    bool param1_ok = param1 == TY_UINT || param1 == TY_INT;
    return hir_call_arg_count[call_node] == 2u &&
           (call_return_type[callee_token] == TY_INT || call_return_type[fn_token] == TY_INT) &&
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

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    bool callee_return_ok =
        call_return_type[callee_token] == TY_INT || call_return_type[callee_token] == TY_UINT;
    bool fn_return_ok =
        call_return_type[fn_token] == TY_INT || call_return_type[fn_token] == TY_UINT;
    return hir_call_arg_count[call_node] == 0u && (callee_return_ok || fn_return_ok);
}

bool host_no_arg_i32_expr_and_len(uint call_node, uint language_symbol, uint wasm_func_index, out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);
    if (!host_no_arg_i32_call_node(call_node, language_symbol))
        return false;

    len = 1u + u32_leb_len(wasm_func_index);
    return true;
}

bool host_process_arg_len_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_ARG_LEN) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_ARG_LEN)))
    {
        return false;
    }

    return hir_call_arg_count[call_node] == 1u &&
           (call_return_type[callee_token] == TY_INT || call_return_type[fn_token] == TY_INT) &&
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

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_ARG_READ) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_ARG_READ)))
    {
        return false;
    }

    uint param1 = host_param_type(fn_token, 1u);
    uint param2 = host_param_type(fn_token, 2u);
    bool param1_ok = param1 == TY_UINT || param1 == TY_INT;
    bool param2_ok = param2 == TY_UINT || param2 == TY_INT;
    return hir_call_arg_count[call_node] == 3u &&
           (call_return_type[callee_token] == TY_INT || call_return_type[fn_token] == TY_INT) &&
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

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR)))
    {
        return false;
    }

    return hir_call_arg_count[call_node] == 1u &&
           (call_return_type[callee_token] == TY_UINT ||
            call_return_type[callee_token] == TY_INT ||
            call_return_type[fn_token] == TY_UINT ||
            call_return_type[fn_token] == TY_INT);
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
    if (form == HIR_EXPR_NAME)
    {
        return name_const_record_value(node, value);
    }
    return false;
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

bool binary_const_value(uint form, uint left, uint right, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_EQ) { value = left == right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_NE) { value = left != right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LT) { value = int(left) < int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GT) { value = int(left) > int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LE) { value = int(left) <= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GE) { value = int(left) >= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_ADD) { value = left + right; return true; }
    if (form == HIR_EXPR_SUB) { value = left - right; return true; }
    if (form == HIR_EXPR_MUL) { value = left * right; return true; }
    if (form == HIR_EXPR_AND) { value = left != 0u && right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_OR) { value = left != 0u || right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_BIT_OR) { value = left | right; return true; }
    if (form == HIR_EXPR_BIT_XOR) { value = left ^ right; return true; }
    if (form == HIR_EXPR_BIT_AND) { value = left & right; return true; }
    if (form == HIR_EXPR_SHL) { value = left << min(right, 31u); return true; }
    if (form == HIR_EXPR_SHR) { value = uint(int(left) >> min(right, 31u)); return true; }
    if (right == 0u)
        return false;
    if (form == HIR_EXPR_DIV) { value = uint(int(left) / int(right)); return true; }
    if (form == HIR_EXPR_MOD) { value = uint(int(left) % int(right)); return true; }
    return false;
}

bool push_eval_node(
    inout uint nodes[MAX_CONST_EVAL_STACK],
    inout uint states[MAX_CONST_EVAL_STACK],
    inout uint sp,
    uint node)
{
    if (sp >= MAX_CONST_EVAL_STACK)
        return false;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    nodes[sp] = node;
    states[sp] = 0u;
    sp += 1u;
    return true;
}

bool const_expr_value(uint root_node, out uint value)
{
    value = 0u;

    uint nodes[MAX_CONST_EVAL_STACK];
    uint states[MAX_CONST_EVAL_STACK];
    uint values[MAX_CONST_EVAL_STACK];
    uint sp = 0u;
    uint vsp = 0u;
    if (!push_eval_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_CONST_EVAL_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        uint state = states[sp - 1u];
        uint form = expr_form(node);
        uint atom = 0u;
        if (state == 0u && const_atom_value(node, atom))
        {
            if (vsp >= MAX_CONST_EVAL_STACK)
                return false;
            values[vsp] = atom;
            vsp += 1u;
            sp -= 1u;
            continue;
        }
        if (state == 0u && form == HIR_EXPR_NAME)
        {
            uint init_expr = INVALID;
            if (!name_let_initializer_expr(node, init_expr))
                return false;
            nodes[sp - 1u] = resolve_expr_node(init_expr);
            states[sp - 1u] = 0u;
            continue;
        }

        if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
        {
            if (state == 0u)
            {
                states[sp - 1u] = 1u;
                if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                    return false;
                continue;
            }
            if (vsp < 1u)
                return false;
            uint inner = values[vsp - 1u];
            vsp -= 1u;
            uint result = 0u;
            if (!unary_const_value(form, inner, result))
                return false;
            values[vsp] = result;
            vsp += 1u;
            sp -= 1u;
            continue;
        }

        bool binary =
            form == HIR_EXPR_EQ || form == HIR_EXPR_NE ||
            form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
            form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
            form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
            form == HIR_EXPR_MUL || form == HIR_EXPR_AND ||
            form == HIR_EXPR_OR || form == HIR_EXPR_MOD ||
            form == HIR_EXPR_DIV || form == HIR_EXPR_BIT_OR ||
            form == HIR_EXPR_BIT_XOR || form == HIR_EXPR_BIT_AND ||
            form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
        if (!binary)
            return false;

        if (state == 0u)
        {
            states[sp - 1u] = 1u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }
        if (state == 1u)
        {
            states[sp - 1u] = 2u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
                return false;
            continue;
        }
        if (vsp < 2u)
            return false;
        uint right = values[vsp - 1u];
        uint left = values[vsp - 2u];
        vsp -= 2u;
        uint result = 0u;
        if (!binary_const_value(form, left, right, result))
            return false;
        values[vsp] = result;
        vsp += 1u;
        sp -= 1u;
    }

    if (sp != 0u || vsp != 1u)
        return false;
    value = values[0u];
    return true;
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

    uint control = hir_nearest_enclosing_control_node[node];
    for (uint i = 0u; i < MAX_CONTROL_BRANCH_DEPTH; i += 1u)
    {
        if (!valid_node(control))
            return false;
        if ((hir_kind[control] == HIR_FOR_STMT || hir_kind[control] == HIR_STMT) &&
            stmt_record_slot(control, 0u) == STMT_RECORD_KIND_FOR &&
            stmt_record_slot(control, 1u) == decl_token)
        {
            if (!function_non_param_local_index(decl_token, owner_fn, local_index))
                return false;
            decl_token = local_index;
            return true;
        }
        control = hir_nearest_enclosing_control_node[control];
    }
    return false;
}

bool expr_mentions_local_let(uint root_node)
{
    uint nodes[MAX_CONST_EVAL_STACK];
    uint states[MAX_CONST_EVAL_STACK];
    uint sp = 0u;
    if (!push_eval_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_CONST_EVAL_STEPS; step += 1u)
    {
        if (sp == 0u)
            return false;

        uint node = resolve_expr_node(nodes[sp - 1u]);
        sp -= 1u;
        if (!valid_node(node))
            return false;

        uint decl_token = INVALID;
        if (local_decl_token_for_name_expr(node, decl_token))
            return true;

        uint form = expr_form(node);
        if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
        {
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }

        bool binary =
            form == HIR_EXPR_EQ || form == HIR_EXPR_NE ||
            form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
            form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
            form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
            form == HIR_EXPR_MUL || form == HIR_EXPR_AND ||
            form == HIR_EXPR_OR || form == HIR_EXPR_MOD ||
            form == HIR_EXPR_DIV || form == HIR_EXPR_BIT_OR ||
            form == HIR_EXPR_BIT_XOR || form == HIR_EXPR_BIT_AND ||
            form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
        if (binary)
        {
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)) ||
                !push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
            {
                return false;
            }
        }
    }
    return false;
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
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), inner))
            return false;
        return unary_const_value(form, inner, value);
    }

    return false;
}

bool direct_call_arg_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    if (expr_non_call_atom_and_len(node, len))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner_len = 0u;
        if (!expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = inner_len + 1u;
        return true;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = 0u;
        if (!expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = 2u + inner_len + 1u;
        return true;
    }
    if (expr_binary_op_supported(form))
    {
        uint left_len = 0u;
        uint right_len = 0u;
        if (!expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
            !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
        {
            return false;
        }
        len = left_len + right_len + 1u;
        return true;
    }

    return false;
}

bool direct_call_arg_scalar_and_len(uint node, out uint len)
{
    len = 0u;
    if (expr_non_call_atom_and_len(node, len))
        return true;

    uint value = 0u;
    if (!direct_call_arg_const_value(node, value))
        return false;
    len = 1u + i32_sleb_len(value);
    return true;
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

    uint total = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i >= arg_count)
            continue;
        uint arg_node = direct_call_arg_node(node, i);
        uint arg_len = 0u;
        if (!direct_call_arg_scalar_and_len(arg_node, arg_len) || arg_len == 0u)
            return false;
        total += arg_len;
    }
    len = total;
    return true;
}

bool direct_call_simple_args_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return false;

    uint total = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i >= arg_count)
            continue;
        uint arg_node = direct_call_arg_node(node, i);
        uint arg_len = 0u;
        if (!direct_call_arg_expr_and_len(arg_node, arg_len) || arg_len == 0u)
            return false;
        total += arg_len;
    }
    len = total;
    return true;
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
    uint left_atom_len = 0u;
    uint right_atom_len = 0u;
    uint left_call_len = 0u;
    uint right_call_len = 0u;
    bool left_atom = expr_non_call_atom_and_len(left, left_atom_len);
    bool right_atom = expr_non_call_atom_and_len(right, right_atom_len);
    bool left_call = direct_call_simple_args_expr_and_len(left, left_call_len);
    bool right_call = direct_call_simple_args_expr_and_len(right, right_call_len);

    if (left_atom && right_call)
    {
        call_node = resolve_expr_node(right);
        atom_node = left;
        call_side = 1u;
        len = left_atom_len + right_call_len + 1u;
        return true;
    }
    if (left_call && right_atom)
    {
        call_node = resolve_expr_node(left);
        atom_node = right;
        call_side = 0u;
        len = left_call_len + right_atom_len + 1u;
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
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    if (expr_atom_and_len(node, len))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner_len = 0u;
        if (!expr_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = inner_len + 1u;
        return true;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = 0u;
        if (!expr_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = 2u + inner_len + 1u;
        return true;
    }
    if (expr_binary_op_supported(form))
    {
        uint left_len = 0u;
        uint right_len = 0u;
        if (!expr_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
            !expr_atom_and_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
        {
            return false;
        }
        len = left_len + right_len + 1u;
        return true;
    }
    return false;
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

bool supported_let_const_fragment(uint node, out uint decl_token, out uint value, out uint len)
{
    decl_token = INVALID;
    value = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    uint init_expr = stmt_record_slot(node, 2u);
    if (!valid_token(decl_token) || !valid_node(init_expr) || !const_expr_value(init_expr, value))
        return false;

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
    decl_token = local_index;
    len = 1u + i32_sleb_len(value) + local_set_len(local_index);
    return true;
}

bool supported_assign_const_fragment(
    uint node,
    out uint target_decl,
    out uint rhs_value,
    out uint op,
    out uint len)
{
    target_decl = INVALID;
    rhs_value = 0u;
    op = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return false;
    }

    uint target = stmt_record_slot(node, 1u);
    uint rhs = stmt_record_slot(node, 2u);
    op = stmt_record_slot(node, 3u);
    if (!assign_op_supported(op) ||
        !local_decl_token_for_name_expr(target, target_decl) ||
        !const_expr_value(rhs, rhs_value))
    {
        return false;
    }
    if ((op == ASSIGN_OP_DIV || op == ASSIGN_OP_MOD) && rhs_value == 0u)
        return false;

    uint rhs_len = 1u + i32_sleb_len(rhs_value);
    len = op == ASSIGN_OP_SET
              ? rhs_len + local_set_len(target_decl)
              : local_get_len(target_decl) + rhs_len + 1u + local_set_len(target_decl);
    return true;
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
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
        return false;
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
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index))
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
    rhs_node = stmt_record_slot(node, 2u);
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

bool print_call_value_and_len(uint call_node, out uint value, out uint len)
{
    value = 0u;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    if (!valid_node(arg_node) || !const_expr_value(arg_node, value))
        return false;

    len = 1u + i32_sleb_len(value) + 2u;
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

bool return_expr_value_and_len(uint return_node, out uint value, out uint len)
{
    value = 0u;
    len = 0u;
    uint expr = stmt_record_slot(return_node, 1u);
    if (!valid_node(expr) || !const_expr_value(expr, value))
        return false;

    len = 1u + i32_sleb_len(value) + 1u;
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
    uint expr = stmt_record_slot(return_node, 1u);
    uint expr_len = 0u;
    if (!valid_node(expr) || !expr_simple_and_len(expr, expr_len))
        return false;

    expr_node = expr;
    len = expr_len + 1u;
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

bool nearest_while_loop_for_node(uint node, out uint loop_node)
{
    loop_node = valid_node(node) ? hir_nearest_loop_node[node] : INVALID;
    if (!valid_node(loop_node))
        return false;
    uint stmt_kind = stmt_record_slot(loop_node, 0u);
    return (hir_kind[loop_node] == HIR_WHILE_STMT && stmt_kind == STMT_RECORD_KIND_WHILE) ||
           (hir_kind[loop_node] == HIR_FOR_STMT && stmt_kind == STMT_RECORD_KIND_FOR);
}

bool loop_control_branch_depth(uint node, out uint depth)
{
    depth = 0u;
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_BREAK_STMT && hir_kind[node] != HIR_CONTINUE_STMT))
    {
        return false;
    }

    uint loop_node = INVALID;
    if (!nearest_while_loop_for_node(node, loop_node))
        return false;

    uint loop_kind = hir_kind[loop_node];
    depth = hir_kind[node] == HIR_BREAK_STMT
                ? (loop_kind == HIR_FOR_STMT ? 2u : 1u)
                : 0u;
    uint control = hir_nearest_enclosing_control_node[node];
    for (uint i = 0u; i < MAX_CONTROL_BRANCH_DEPTH; i += 1u)
    {
        if (!valid_node(control))
            return false;
        if (control == loop_node)
            return true;

        uint kind = hir_kind[control];
        if (kind == HIR_IF_STMT)
        {
            depth += 1u;
            control = hir_nearest_enclosing_control_node[control];
            continue;
        }

        return false;
    }
    return false;
}

bool loop_control_fragment_and_len(uint node, out uint depth, out uint len)
{
    depth = 0u;
    len = 0u;
    uint stmt_kind = stmt_record_slot(node, 0u);
    if ((hir_kind[node] == HIR_BREAK_STMT && stmt_kind != STMT_RECORD_KIND_BREAK) ||
        (hir_kind[node] == HIR_CONTINUE_STMT && stmt_kind != STMT_RECORD_KIND_CONTINUE))
    {
        return false;
    }
    if (!loop_control_branch_depth(node, depth))
        return false;

    len = 1u + u32_leb_len(depth);
    return true;
}

bool function_end_token_and_len(uint fn_node, out uint end_token, out uint len)
{
    end_token = INVALID;
    len = 0u;
    if (!valid_node(fn_node) || hir_kind[fn_node] != HIR_FN)
        return false;

    uint fn_token = hir_token_pos[fn_node];
    if (!supported_function_token(fn_token))
        return false;

    uint body_node = INVALID;
    uint active_count = active_hir_node_count();
    for (uint node = fn_node + 1u; node < active_count; node += 1u)
    {
        if (parent[node] == fn_node &&
            hir_kind[node] == HIR_BLOCK &&
            hir_nearest_block_node[node] == node)
        {
            body_node = node;
            break;
        }
    }
    if (!valid_node(body_node))
        return false;

    uint end = hir_token_end[body_node];
    if (end == 0u || end == INVALID)
        return false;

    end_token = end - 1u;
    if (!valid_token(end_token))
        return false;

    len = 2u;
    return true;
}

bool function_end_fragment_for_node(
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

    uint end_token = INVALID;
    uint len = 0u;
    if (!function_end_token_and_len(node, end_token, len))
        return false;

    token_i = end_token * 2u + 1u;
    fragment_len = len;
    fragment_meta = uint4(BODY_FRAGMENT_FUNCTION_END, 0u, 0u, end_token);
    return true;
}

bool body_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    uint let_count,
    uint let_max_token,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return false;

    if (hir_kind[node] == HIR_FN &&
        supported_function_token(token))
    {
        token_i = token;
        uint local_count = local_decl_count_for_function_token(token);
        uint body_size = wasm_func_body_len_by_token[token];
        fragment_len = 5u + local_decl_fragment_len_from_count(local_count);
        fragment_meta = uint4(
            BODY_FRAGMENT_FUNCTION_HEADER,
            body_size,
            local_count,
            token);
        return true;
    }

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;
    return_token = wasm_func_return_token_by_token[owner_fn];
    if (!valid_token(return_token))
        return false;

    if (hir_kind[node] == HIR_RETURN_STMT)
    {
        uint return_expr_node = INVALID;
        uint return_value = 0u;
        uint return_len = 0u;
        uint return_decl = INVALID;
        uint return_call_node = INVALID;
        uint return_atom_node = INVALID;
        uint return_op = 0u;
        uint return_call_side = 0u;
        if (return_binary_direct_call_fragment_and_len(
                node,
                return_call_node,
                return_atom_node,
                return_op,
                return_call_side,
                return_len))
        {
            token_i = token;
            fragment_len = return_len;
            fragment_meta = uint4(
                BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32,
                return_call_node,
                return_atom_node,
                return_op | (return_call_side << 8u));
            return true;
        }
        if (return_direct_call_fragment_and_len(node, return_expr_node, return_len))
        {
            token_i = token;
            fragment_len = return_len;
            fragment_meta = uint4(
                BODY_FRAGMENT_RETURN_DIRECT_CALL_I32,
                return_expr_node,
                fragment_len,
                token_i);
            return true;
        }
        if (return_expr_fragment_and_len(node, return_expr_node, return_len))
        {
            token_i = token;
            fragment_len = return_len;
            fragment_meta = uint4(
                BODY_FRAGMENT_RETURN_EXPR_I32,
                return_expr_node,
                fragment_len,
                token_i);
            return true;
        }
        if (return_expr_local_and_len(node, return_decl, return_len))
        {
            token_i = token;
            fragment_len = return_len;
            fragment_meta = uint4(
                BODY_FRAGMENT_RETURN_LOCAL_I32,
                return_decl,
                fragment_len,
                token_i);
            return true;
        }
        if (return_expr_value_and_len(node, return_value, return_len))
        {
            token_i = token;
            fragment_len = return_len;
            fragment_meta = uint4(
                BODY_FRAGMENT_RETURN_I32,
                return_value,
                fragment_len,
                token_i);
            return true;
        }
        return false;
    }

    if (hir_kind[node] == HIR_CALL_EXPR &&
        print_call_node(node))
    {
        uint expr_node = INVALID;
        uint value = 0u;
        uint len = 0u;
        uint decl_token = INVALID;
        if (print_call_direct_call_and_len(node, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_PRINT_DIRECT_CALL_I64,
                expr_node,
                fragment_len,
                token_i);
            return true;
        }
        if (print_call_expr_and_len(node, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_PRINT_EXPR_I64,
                expr_node,
                fragment_len,
                token_i);
            return true;
        }
        if (print_call_local_and_len(node, decl_token, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_PRINT_LOCAL_I64,
                decl_token,
                fragment_len,
                token_i);
            return true;
        }

        if (print_call_value_and_len(node, value, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_PRINT_I64,
                value,
                fragment_len,
                token_i);
            return true;
        }
    }

    if (hir_kind[node] == HIR_LET_STMT)
    {
        uint decl_token = INVALID;
        uint expr_node = INVALID;
        uint value = 0u;
        uint len = 0u;
        if (supported_let_i32_array_data_ptr_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (supported_let_host_stdout_write_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (supported_let_host_process_argc_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_HOST_NO_ARG_I32,
                decl_token,
                expr_node,
                WASM_PROCESS_ARGC_FUNC_INDEX);
            return true;
        }
        if (supported_let_host_process_arg_len_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (supported_let_host_process_arg_read_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (supported_let_host_secure_u32_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_HOST_NO_ARG_I32,
                decl_token,
                expr_node,
                WASM_RANDOM_SECURE_U32_FUNC_INDEX);
            return true;
        }
        if (supported_let_host_unix_seconds_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_HOST_NO_ARG_I32,
                decl_token,
                expr_node,
                WASM_TIME_UNIX_SECONDS_FUNC_INDEX);
            return true;
        }
        if (supported_let_direct_call_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_DIRECT_CALL_I32,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (supported_let_expr_fragment(node, decl_token, expr_node, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                BODY_FRAGMENT_LET_EXPR_I32,
                decl_token,
                expr_node,
                token_i);
            return true;
        }
        if (!supported_let_const_fragment(node, decl_token, value, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            BODY_FRAGMENT_LET_CONST_I32,
            decl_token,
            value,
            token_i);
        return true;
    }

    if (hir_kind[node] == HIR_STMT &&
        stmt_record_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
    {
        uint target_decl = INVALID;
        uint rhs_node = INVALID;
        uint rhs_value = 0u;
        uint op = 0u;
        uint len = 0u;
        if (supported_assign_direct_call_fragment(node, target_decl, rhs_node, op, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                op == ASSIGN_OP_SET
                    ? BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32
                    : BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32,
                target_decl,
                rhs_node,
                op);
            return true;
        }
        if (supported_assign_expr_fragment(node, target_decl, rhs_node, op, len))
        {
            token_i = token;
            fragment_len = len;
            fragment_meta = uint4(
                op == ASSIGN_OP_SET
                    ? BODY_FRAGMENT_ASSIGN_EXPR_I32
                    : BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32,
                target_decl,
                rhs_node,
                op);
            return true;
        }
        if (!supported_assign_const_fragment(node, target_decl, rhs_value, op, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            op == ASSIGN_OP_SET
                ? BODY_FRAGMENT_ASSIGN_CONST_I32
                : BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32,
            target_decl,
            rhs_value,
            op);
        return true;
    }

    if (hir_kind[node] == HIR_WHILE_STMT &&
        stmt_record_slot(node, 0u) == STMT_RECORD_KIND_WHILE)
    {
        uint condition_node = INVALID;
        uint len = 0u;
        if (!while_open_fragment_and_len(node, condition_node, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            BODY_FRAGMENT_WHILE_OPEN_I32,
            condition_node,
            fragment_len,
            token_i);
        return true;
    }

    if (hir_kind[node] == HIR_IF_STMT &&
        stmt_record_slot(node, 0u) == STMT_RECORD_KIND_IF)
    {
        uint condition_node = INVALID;
        uint len = 0u;
        if (!if_open_fragment_and_len(node, condition_node, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            BODY_FRAGMENT_IF_OPEN_I32,
            condition_node,
            fragment_len,
            token_i);
        return true;
    }

    if ((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_record_slot(node, 0u) == STMT_RECORD_KIND_FOR)
    {
        uint binding_token = INVALID;
        uint range_node = INVALID;
        uint end_local_token = INVALID;
        uint len = 0u;
        if (!for_open_range_fragment_and_len(
                node,
                binding_token,
                range_node,
                end_local_token,
                len))
        {
            return false;
        }
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            BODY_FRAGMENT_FOR_OPEN_RANGE_I32,
            binding_token,
            range_node,
            end_local_token);
        return true;
    }

    if ((hir_kind[node] == HIR_BREAK_STMT ||
         hir_kind[node] == HIR_CONTINUE_STMT))
    {
        uint depth = 0u;
        uint len = 0u;
        if (!loop_control_fragment_and_len(node, depth, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(BODY_FRAGMENT_BRANCH, depth, fragment_len, token_i);
        return true;
    }

    return false;
}
