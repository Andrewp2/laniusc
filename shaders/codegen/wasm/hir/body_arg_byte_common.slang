// Byte helpers for aggregate direct-call argument scatter.

import gpu_index;
import call_relocation;
import expr_span_lookup;
import expr_emission_common;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
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
StructuredBuffer<uint2> expr_node_emission;
StructuredBuffer<uint2> expr_subtree_total;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;

static const uint INVALID = 0xffffffffu;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint LANGUAGE_SYMBOL_OPEN_READ_PATH = 20u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint HOST_STR_CALL_OPEN_READ_PATH = 1u;
static const uint HOST_STR_CALL_OPEN_WRITE_PATH = 2u;
static const uint HOST_STR_CALL_WRITE_TEXT = 3u;
static const uint WASM_STD_OPEN_READ_PATH_FUNC_INDEX = 28u;
static const uint WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX = 29u;
static const uint WASM_STD_WRITE_TEXT_FUNC_INDEX = 30u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;
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
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
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
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
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

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < path_count_out[0u];
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

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
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

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token) || language_symbol >= 63u)
        return false;
    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
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

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
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

uint local_decl_initializer_expr_type(uint init_expr)
{
    if (!valid_node(init_expr))
        return TY_UNKNOWN;
    uint root = hir_expr_result_root_node[init_expr];
    uint form = valid_node(root) ? expr_form(root) : expr_form(init_expr);
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_INT;
    return TY_UNKNOWN;
}

uint local_decl_type(uint decl_token)
{
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    uint ty = local_decl_initializer_expr_type(init_expr);
    if (ty == TY_UNKNOWN)
        ty = visible_type_for_token(decl_token);
    return ty == TY_UNKNOWN ? TY_INT : ty;
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
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

bool direct_call_has_receiver_arg(uint call_node, uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    uint member_node = method_member_node_for_call(call_node);
    if (!valid_node(member_node))
        return false;
    uint receiver_node = hir_member_receiver_node[member_node];
    if (!valid_node(receiver_node))
        return false;
    uint explicit_arg_count = hir_call_arg_count[call_node];
    return call_param_count[fn_token] == explicit_arg_count + 1u;
}

uint direct_call_abi_arg_node(uint call_node, uint fn_token, uint ordinal)
{
    if (direct_call_has_receiver_arg(call_node, fn_token))
    {
        if (ordinal == 0u)
        {
            uint member_node = method_member_node_for_call(call_node);
            return valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
        }
        return direct_call_arg_node(call_node, ordinal - 1u);
    }
    return direct_call_arg_node(call_node, ordinal);
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

bool function_decl_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    if (function_param_local_index(decl_token, fn_token, local_index))
        return true;
    return function_non_param_local_index(decl_token, fn_token, local_index);
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

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
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

bool let_initializer_for_decl_token(uint decl_token, out uint init_expr)
{
    init_expr = INVALID;
    if (!valid_token(decl_token))
        return false;

    init_expr = body_let_init_expr_by_decl_token[decl_token];
    return valid_node(init_expr) && hir_kind[init_expr] == HIR_EXPR;
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
        return name_const_record_value(node, value);
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

bool expr_atom_is_f32(uint node)
{
    uint member_node = member_expr_node_from_expr(node);
    if (valid_node(member_node))
    {
        uint member_name = hir_member_name_token[member_node];
        return visible_type_for_token(member_name) == TY_FLOAT;
    }
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
    return false;
}

uint expr_semantic_type(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = call_return_type[token];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

bool expr_operand_result_is_f32(uint node)
{
    uint ty = expr_semantic_type(node);
    if (ty != TY_UNKNOWN)
        return ty == TY_FLOAT;
    uint resolved = resolve_expr_node(node);
    if (!valid_node(resolved))
        return false;
    uint form = expr_form(resolved);
    if (form == HIR_EXPR_NEG)
        return expr_atom_is_f32(expr_record_slot(resolved, EXPR_RECORD_LEFT));
    if (form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL || form == HIR_EXPR_DIV)
    {
        return expr_atom_is_f32(expr_record_slot(resolved, EXPR_RECORD_LEFT)) ||
               expr_atom_is_f32(expr_record_slot(resolved, EXPR_RECORD_RIGHT));
    }
    return expr_atom_is_f32(node);
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
    if (expr_operand_result_is_f32(left) || expr_operand_result_is_f32(right))
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

uint aggregate_expr_span_byte(uint node, uint byte_i)
{
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_MEMBER_EXPR && expr_form(node) != HIR_EXPR_NAME))
    {
        node = resolve_expr_node(node);
    }
    if (!valid_node(node))
        return 0u;
    uint2 total = expr_subtree_total[node];
    uint span_start = 0u;
    uint span_len = 0u;
    if (total.y != 0u || total.x == 0u || byte_i >= total.x ||
        !wasm_expr_node_span(node, gParams.n_hir_nodes, span_start, span_len))
    {
        return 0u;
    }
    uint subtree_end = span_start + span_len;
    if (subtree_end < total.x)
        return 0u;
    uint owner = INVALID;
    uint owner_byte = 0u;
    if (!wasm_expr_span_byte_owner(
            node,
            gParams.n_hir_nodes,
            subtree_end - total.x + byte_i,
            owner,
            owner_byte))
    {
        return 0u;
    }
    uint byte = 0u;
    return wasm_expr_emission_byte(expr_node_emission[owner], owner_byte, byte)
               ? byte
               : 0u;
}

uint aggregate_address_expr_byte(uint node, uint byte_i)
{
    uint len = 0u;
    if (!aggregate_address_expr_and_len(node, len) || byte_i >= len)
        return 0u;

    uint resolved = resolve_expr_node(node);
    if (valid_node(resolved) && expr_form(resolved) == HIR_EXPR_NAME)
        return aggregate_name_address_expr_byte(resolved, byte_i);
    return aggregate_expr_span_byte(node, byte_i);
}

uint member_expr_node_from_expr(uint node)
{
    if (valid_node(node) &&
        hir_kind[node] == HIR_MEMBER_EXPR &&
        valid_token(hir_member_name_token[node]))
    {
        return node;
    }
    node = resolve_expr_node(node);
    return valid_node(node) &&
           hir_kind[node] == HIR_MEMBER_EXPR &&
           valid_token(hir_member_name_token[node])
               ? node
               : INVALID;
}

bool aggregate_member_address_and_len(uint node, out uint len)
{
    len = 0u;
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return false;

    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return false;

    if (member_result_field_index[member_name] == INVALID)
        return false;
    uint2 total = expr_subtree_total[node];
    if (total.y != 0u || total.x == 0u)
        return false;
    len = total.x;
    return true;
}

uint aggregate_member_address_byte(uint node, uint byte_i)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return 0u;

    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return 0u;

    if (member_result_field_index[member_name] == INVALID)
        return 0u;
    uint2 total = expr_subtree_total[node];
    return total.y == 0u && byte_i < total.x
               ? aggregate_expr_span_byte(node, byte_i)
               : 0u;
}

bool expr_non_call_atom_and_len(uint node, out uint len)
{
    len = 0u;
    if (aggregate_member_address_and_len(node, len))
        return true;
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
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
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
    if (direct_call_arg_const_value(node, value))
    {
        len = 1u + i32_sleb_len(value);
        return true;
    }
    return false;
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
        if (!string_value_expr_and_len(direct_call_arg_node(call_node, 0u), string_len))
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
            !string_value_expr_and_len(direct_call_arg_node(call_node, 1u), string_len))
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

bool direct_call_arg_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
    {
        len = atom_len;
        return true;
    }

    if (host_string_i32_expr_and_len(node, len))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
    {
        uint inner_len = 0u;
        if (!expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = inner_len + (form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u));
        return true;
    }

    uint left_len = 0u;
    uint right_len = 0u;
    if (!expr_binary_op_supported(form) ||
        expr_binary_op_byte_for_node(node) == 0u ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
    {
        return false;
    }

    len = left_len + right_len + 1u;
    return true;
}

uint expr_non_call_atom_byte(uint node, uint byte_i)
{
    uint member_len = 0u;
    if (aggregate_member_address_and_len(node, member_len))
        return aggregate_member_address_byte(node, byte_i);
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return local_get_byte(local_index, byte_i);

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
        return i32_const_byte(value, byte_i);
    }
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    return 0u;
}

uint direct_call_arg_scalar_byte(uint node, uint byte_i)
{
    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return expr_non_call_atom_byte(node, byte_i);

    uint value = 0u;
    if (direct_call_arg_const_value(node, value))
        return i32_const_byte(value, byte_i);
    return 0u;
}

uint string_ptr_len_call_byte(uint string_node, uint wasm_func_index, uint byte_i)
{
    uint len = 0u;
    if (!string_value_expr_and_len(string_node, len))
        return 0u;

    if (byte_i < len)
        return string_value_expr_byte(string_node, byte_i);
    uint call_start = len;
    if (byte_i == call_start)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_start - 1u);
}

uint handle_string_call_byte(uint call_node, uint wasm_func_index, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint handle_node = direct_call_arg_node(call_node, 0u);
    uint handle_len = 0u;
    if (!direct_call_arg_scalar_and_len(handle_node, handle_len))
        return 0u;
    if (byte_i < handle_len)
        return direct_call_arg_scalar_byte(handle_node, byte_i);

    uint string_node = direct_call_arg_node(call_node, 1u);
    uint len = 0u;
    if (!string_value_expr_and_len(string_node, len))
        return 0u;

    uint string_start = handle_len;
    if (byte_i < string_start + len)
        return string_value_expr_byte(string_node, byte_i - string_start);
    uint call_start = string_start + len;
    if (byte_i == call_start)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_start - 1u);
}

uint host_string_i32_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint len = 0u;
    if (host_string_i32_call_expr_and_len(
            node,
            LANGUAGE_SYMBOL_OPEN_READ_PATH,
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_READ_PATH,
            len))
    {
        return string_ptr_len_call_byte(
            direct_call_arg_node(node, 0u),
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            byte_i);
    }
    if (host_string_i32_call_expr_and_len(
            node,
            LANGUAGE_SYMBOL_OPEN_WRITE_PATH,
            WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_WRITE_PATH,
            len))
    {
        return string_ptr_len_call_byte(
            direct_call_arg_node(node, 0u),
            WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
            byte_i);
    }
    if (host_string_i32_call_expr_and_len(
            node,
            LANGUAGE_SYMBOL_WRITE_TEXT,
            WASM_STD_WRITE_TEXT_FUNC_INDEX,
            HOST_STR_CALL_WRITE_TEXT,
            len))
    {
        return handle_string_call_byte(node, WASM_STD_WRITE_TEXT_FUNC_INDEX, byte_i);
    }
    return 0u;
}

uint direct_call_arg_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);

    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return expr_non_call_atom_byte(node, byte_i);

    uint host_len = 0u;
    if (host_string_i32_expr_and_len(node, host_len))
        return host_string_i32_expr_byte(node, byte_i);

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = 0u;
        if (!expr_non_call_atom_and_len(inner, inner_len))
            return 0u;
        if (form == HIR_EXPR_NOT)
        {
            if (byte_i < inner_len)
                return expr_non_call_atom_byte(inner, byte_i);
            return WASM_I32_EQZ;
        }
        if (expr_neg_is_f32(node))
        {
            if (byte_i < inner_len)
                return expr_non_call_atom_byte(inner, byte_i);
            return WASM_F32_NEG;
        }
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
        if (byte_i < 2u + inner_len)
            return expr_non_call_atom_byte(inner, byte_i - 2u);
        return WASM_I32_SUB;
    }

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_len = 0u;
    uint right_len = 0u;
    if (!expr_binary_op_supported(form) ||
        !expr_non_call_atom_and_len(left, left_len) ||
        !expr_non_call_atom_and_len(right, right_len))
    {
        return 0u;
    }
    if (byte_i < left_len)
        return expr_non_call_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return expr_non_call_atom_byte(right, byte_i - left_len);
    return expr_binary_op_byte_for_node(node);
}

uint direct_call_abi_arg_non_call_byte(uint node, uint fn_token, uint ordinal, uint byte_i)
{
    uint param_ty = call_param_type_value(fn_token, ordinal);
    if (param_ty == TY_STRING)
        return string_value_expr_byte(node, byte_i);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return direct_call_arg_expr_byte(node, byte_i);
}

bool direct_call_arg_abi_expr_and_len(uint node, uint param_ty, out uint len)
{
    if (param_ty == TY_STRING)
        return string_value_expr_and_len(node, len);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_and_len(node, len);
    return direct_call_arg_expr_and_len(node, len);
}

uint direct_call_abi_arg_byte(uint node, uint fn_token, uint ordinal, uint byte_i)
{
    return direct_call_abi_arg_non_call_byte(node, fn_token, ordinal, byte_i);
}

// Non-scalar ABI records are scattered separately from scalar expression
// forests. Keeping this entry point independent of function/ordinal lookup
// prevents the non-scalar byte shader from retaining the entire scalar
// expression helper graph.
uint direct_call_abi_non_scalar_arg_byte(uint node, uint param_ty, uint byte_i)
{
    if (param_ty == TY_STRING)
        return string_value_expr_byte(node, byte_i);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return 0u;
}
