// Array-specific body length and local accounting for the WASM HIR backend.

import atomics;
import gpu_index;
import prefix_scan;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parser_feature_flags;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint2> expr_subtree_total;
StructuredBuffer<uint2> expr_subtree_features;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> struct_init_field_index;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint INVALID = 0xffffffffu;
static const uint PARSER_FEATURE_ARRAYS = 0x00000002u;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint HIR_NONE = 0u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
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
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint BODY_FRAGMENT_LET_EXPR_I32 = 9u;
static const uint BODY_FRAGMENT_RETURN_EXPR_I32 = 13u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_ARRAY_STORE_I32 = 31u;
static const uint BODY_FRAGMENT_ARRAY_STORE_ATOM_I32 = 56u;
static const uint BODY_FRAGMENT_ASSIGN_INDEX_I32 = 57u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_INDEX_I32 = 58u;
static const uint BODY_FRAGMENT_AGG_FIELD_STORE_I32 = 40u;
static const uint BODY_FRAGMENT_AGG_DIRECT_COPY_I32 = 43u;
static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FEATURE_DIRECT = 1u << 1u;
static const uint BODY_FEATURE_HOST = 1u << 2u;
static const uint BODY_FEATURE_ARRAYS = 1u << 3u;
static const uint BODY_FEATURE_MEMBER_EXPR = 1u << 4u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FEATURE_LET_DIRECT = 1u << 6u;
static const uint BODY_FEATURE_LET_AGG_DIRECT = 1u << 9u;
static const uint BODY_FEATURE_AGG_COPY = 1u << 11u;
static const uint BODY_FEATURE_ARRAY_ALLOC = 1u << 12u;

uint body_fragment_feature_mask(uint kind)
{
    if (kind == BODY_FRAGMENT_LET_EXPR_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_EXPR_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 ||
        kind == BODY_FRAGMENT_RETURN_EXPR_I32)
        return BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_MEMBER_EXPR;
    if (kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32)
        return BODY_FEATURE_LET_DIRECT;
    if (kind == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
        return BODY_FEATURE_BINARY_DIRECT;
    if (kind == BODY_FRAGMENT_ARRAY_STORE_I32)
        return BODY_FEATURE_ARRAYS | BODY_FEATURE_MEMBER_EXPR;
    if (kind == BODY_FRAGMENT_ARRAY_STORE_ATOM_I32)
        return BODY_FEATURE_ARRAY_ALLOC;
    if (kind == BODY_FRAGMENT_ASSIGN_INDEX_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_COMPOUND_INDEX_I32)
        return BODY_FEATURE_ARRAY_ALLOC;
    if (kind == BODY_FRAGMENT_LET_ARRAY_I32)
        return BODY_FEATURE_ARRAY_ALLOC;
    if (kind == BODY_FRAGMENT_AGG_FIELD_STORE_I32)
        return BODY_FEATURE_MEMBER_EXPR;
    if (kind == BODY_FRAGMENT_AGG_DIRECT_COPY_I32)
        return BODY_FEATURE_AGG_COPY;
    if (kind == BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32)
        return BODY_FEATURE_LET_AGG_DIRECT;
    return 0u;
}

void publish_fragment_features(uint kind)
{
    uint mask = body_fragment_feature_mask(kind);
    if (mask != 0u)
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, mask);
}
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
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

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
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

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
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
    if (!valid_token(metadata_token)) return INVALID;
    if (call_dependency_decl[metadata_token] != INVALID) return metadata_token;
    uint local_fn = call_fn_index[metadata_token];
    return valid_token(local_fn) ? local_fn : INVALID;
}

bool supported_call_target_token(uint token) { return supported_function_token(token) || (valid_token(token) && call_dependency_decl[token] != INVALID); }
uint wasm_call_target_for_call(uint call_node, uint fn_token) { uint token = call_metadata_token(call_node, call_callee_token(call_node)); return valid_token(token) && call_dependency_decl[token] != INVALID ? 0x80000000u | (call_dependency_decl[token] & 0x7fffffffu) : wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT; }

uint call_return_type_for_call(uint call_node, uint callee_token, uint fn_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    uint metadata_return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : TY_UNKNOWN;
    return metadata_return_ty != TY_UNKNOWN && metadata_return_ty != INVALID
               ? metadata_return_ty
               : call_return_type[fn_token];
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

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
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

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint param_count = function_param_abi_count(fn_token);
    local_index = param_count + decl_token;
    return true;
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

bool aggregate_address_expr_len(uint node, out uint len)
{
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
        len = local_get_len(local_index);
        return true;
    }

    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(base_address);
        return true;
    }

    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return false;
        len = local_get_len(local_index);
        return true;
    }

    return false;
}

uint aggregate_member_len(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return 0u;
    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return 0u;
    uint field_index = member_result_field_index[member_name];
    if (field_index == INVALID)
        return 0u;
    uint address_len = 0u;
    if (!aggregate_address_expr_len(hir_member_receiver_node[node], address_len))
        return 0u;
    return address_len + 2u + u32_leb_len(field_index * 4u);
}

bool local_decl_token_for_name_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token) || visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    if (function_param_local_index(decl_token, owner_fn, local_index))
        return true;

    if (body_let_init_expr_by_decl_token[decl_token] == INVALID)
        return false;
    return function_non_param_local_index(decl_token, owner_fn, local_index);
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

uint array_lit_base_address(uint lit_node)
{
    if (!valid_node(lit_node) || !valid_token(hir_token_pos[lit_node]))
        return 0u;
    return hir_token_pos[lit_node] * 4u;
}

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint agg_local_base_slots(uint decl_token)
{
    return global_exclusive_prefix(
        decl_token,
        256u,
        wasm_agg_local_base_by_token,
        wasm_agg_local_block_prefix);
}

bool array_lit_for_decl_token(uint decl_token, out uint lit_node)
{
    lit_node = INVALID;
    if (!valid_token(decl_token))
        return false;

    uint init_expr = resolve_expr_node(body_let_init_expr_by_decl_token[decl_token]);
    if (!valid_node(init_expr) || hir_kind[init_expr] != HIR_ARRAY_EXPR)
        return false;

    uint context = hir_array_lit_context_stmt_node[init_expr];
    if (!valid_node(context) ||
        hir_kind[context] != HIR_LET_STMT ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET ||
        stmt_record_slot(context, 1u) != decl_token)
    {
        return false;
    }

    lit_node = init_expr;
    return true;
}

bool array_decl_for_name_expr(uint node, out uint decl_token, out uint local_index)
{
    decl_token = INVALID;
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint lit_node = INVALID;
    if (!array_lit_for_decl_token(decl_token, lit_node))
        return false;

    return function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index);
}

bool expr_atom_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint member_len = aggregate_member_len(node);
    if (member_len != 0u)
    {
        len = member_len;
        return true;
    }
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (form == HIR_EXPR_INT)
    {
        len = 1u + i32_sleb_len(hir_expr_int_value[node]);
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        len = 2u;
        return true;
    }
    return false;
}

bool lean_array_atom_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (form == HIR_EXPR_INT)
    {
        len = 1u + i32_sleb_len(hir_expr_int_value[node]);
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        len = 2u;
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
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

bool expr_simple_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint2 total = expr_subtree_total[node];
    uint2 features = expr_subtree_features[node];
    len = total.x;
    return total.y == 0u && features.x == 0u && len != 0u;
}

bool direct_call_arg_expr_len(uint node, out uint len)
{
    return expr_simple_len(node, len);
}

bool aggregate_direct_call_expr_len(
    uint node,
    out uint len,
    out uint fn_token,
    out uint wasm_func_index,
    out uint arg_count,
    out uint detail)
{
    len = 0u;
    fn_token = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    detail = INVALID;

    node = resolve_expr_node(node);
    detail = valid_node(node) ? hir_token_pos[node] : INVALID;
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(node);
    if (valid_token(callee_token))
        detail = callee_token;
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    fn_token = call_fn_token_for_call(node, callee_token);
    if (valid_token(fn_token))
        detail = fn_token;
    if (!supported_call_target_token(fn_token))
        return false;

    uint return_ty = call_return_type_for_call(node, callee_token, fn_token);
    if (return_ty < TY_ARRAY_BASE)
        return false;

    uint explicit_arg_count = hir_call_arg_count[node];
    bool has_receiver_arg = direct_call_has_receiver_arg(node, fn_token);
    arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint target = wasm_call_target_for_call(node, fn_token);
    uint total = 1u + u32_leb_len(target);
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(node, fn_token, i);
        if (valid_node(arg_node))
            detail = hir_token_pos[arg_node];
        uint arg_len = 0u;
        uint param_ty = call_param_type_value(fn_token, i);
        bool ok = param_ty >= TY_ARRAY_BASE
                      ? aggregate_address_expr_len(arg_node, arg_len)
                      : direct_call_arg_expr_len(arg_node, arg_len);
        if (!ok || arg_len == 0u)
            return false;
        total += arg_len;
    }

    wasm_func_index = target;
    len = total;
    detail = INVALID;
    return true;
}

bool index_expr_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_INDEX)
        return false;

    uint decl_token = INVALID;
    uint local_index = INVALID;
    if (!array_decl_for_name_expr(
            expr_record_slot(node, EXPR_RECORD_LEFT),
            decl_token,
            local_index))
    {
        return false;
    }

    uint index_len = 0u;
    if (!lean_array_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT), index_len))
        return false;

    len = local_get_len(local_index) + index_len + 7u;
    return true;
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (!valid_token(fn_token))
        return;
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

void add_func_body_len(uint fn_token, uint len)
{
    if (valid_token(fn_token))
        atomic_u32_add(wasm_func_body_len_by_token, fn_token, len);
}

void add_func_local_token(uint fn_token, uint decl_token)
{
    if (valid_token(fn_token) && valid_token(decl_token))
    {
        uint prior = atomic_u32_compare_exchange(
            wasm_func_local_max_by_token,
            fn_token,
            INVALID,
            decl_token);
        if (prior != INVALID)
            atomic_u32_max(wasm_func_local_max_by_token, fn_token, decl_token);
    }
}

void publish_fragment(uint token_i, uint len, uint4 meta)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = uint4(0u, 0u, 0u, 0u);
    publish_fragment_features(meta.x);
}

void publish_fragment_with_aux(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    publish_fragment_features(meta.x);
}

void publish_fragment_slot(uint slot, uint len, uint4 meta, uint4 aux)
{
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    publish_fragment_features(meta.x);
}

bool aggregate_lit_let_decl(uint lit_node, out uint let_node, out uint decl_token)
{
    let_node = INVALID;
    decl_token = INVALID;
    if (!valid_node(lit_node) || hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
        return false;

    uint current = hir_struct_lit_context_stmt_node[lit_node];
    if (valid_node(current) &&
        hir_kind[current] == HIR_LET_STMT &&
        stmt_record_slot(current, 0u) == STMT_RECORD_KIND_LET)
    {
        decl_token = stmt_record_slot(current, 1u);
        let_node = current;
        return valid_token(decl_token);
    }
    return false;
}

void account_let_array(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    uint lit_node = INVALID;
    if (!array_lit_for_decl_token(decl_token, lit_node))
        return;

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint base_address = array_lit_base_address(lit_node);
    uint len = 1u + i32_sleb_len(base_address) + local_set_len(local_index);
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, len);
    publish_fragment_slot(
        token * 2u + 1u,
        len,
        uint4(BODY_FRAGMENT_LET_ARRAY_I32, local_index, base_address, token),
        uint4(0u, 0u, 0u, 0u));
}

void account_let_struct_literal(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    uint let_node = INVALID;
    uint decl_token = INVALID;
    if (!aggregate_lit_let_decl(node, let_node, decl_token))
        return;

    if (!valid_token(decl_token) || wasm_agg_local_width_by_token[decl_token] == 0u)
        return;

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint len = 1u + i32_sleb_len(base_address) + local_set_len(local_index);
    uint let_token = hir_token_pos[let_node];
    if (!valid_token(let_token))
        let_token = token;
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, len);
    publish_fragment_slot(
        let_token * 2u + 1u,
        len,
        uint4(BODY_FRAGMENT_LET_ARRAY_I32, local_index, base_address, let_token),
        uint4(0u, 0u, 0u, 0u));
}

void account_let_aggregate_direct_call(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    if (!valid_token(decl_token) || visible_type_for_token(decl_token) < TY_ARRAY_BASE)
        return;

    uint call_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint call_len = 0u;
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    uint detail = token;
    if (!aggregate_direct_call_expr_len(
            call_node,
            call_len,
            fn_token,
            wasm_func_index,
            arg_count,
            detail))
    {
        publish_func_invalid(owner_fn, valid_token(detail) ? detail : token);
        return;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint width = wasm_agg_local_width_by_token[decl_token];
    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint copy_len =
        (1u + i32_sleb_len(base_address)) +
        local_get_len(local_index) +
        (1u + i32_sleb_len(width * 4u)) +
        4u +
        (1u + i32_sleb_len(base_address)) +
        local_set_len(local_index);
    uint call_set_len = call_len + local_set_len(local_index);
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, call_set_len + copy_len);
    publish_fragment_slot(
        token * 2u,
        call_set_len,
        uint4(BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32, local_index, call_node, token),
        uint4(wasm_func_index, arg_count, fn_token, 0u));
    publish_fragment_slot(
        token * 2u + 1u,
        copy_len,
        uint4(BODY_FRAGMENT_AGG_DIRECT_COPY_I32, local_index, decl_token, token),
        uint4(0u, 0u, 0u, 0u));
}

void account_array_element(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] == HIR_ARRAY_EXPR)
        return;

    uint lit_node = hir_array_element_parent_lit[node];
    if (!valid_node(lit_node))
        return;
    if (lit_node == node)
        return;
    if (hir_kind[lit_node] != HIR_ARRAY_EXPR ||
        hir_array_element_ordinal[node] == INVALID)
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint context = hir_array_lit_context_stmt_node[lit_node];
    uint expr_len = 0u;
    if (!valid_node(context) ||
        hir_kind[context] != HIR_LET_STMT ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET ||
        resolve_expr_node(stmt_record_slot(context, 2u)) != lit_node ||
        !expr_simple_len(node, expr_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint address = array_lit_base_address(lit_node) +
                   hir_array_element_ordinal[node] * 4u;
    uint len = 1u + i32_sleb_len(address) + expr_len + 3u;
    uint atom_len = 0u;
    uint kind = lean_array_atom_len(node, atom_len) && atom_len == expr_len
                    ? BODY_FRAGMENT_ARRAY_STORE_ATOM_I32
                    : BODY_FRAGMENT_ARRAY_STORE_I32;
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(kind, address, node, token));
}

void account_struct_field_store(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_NONE)
        return;

    uint lit_node = hir_struct_lit_field_parent_lit[node];
    if (!valid_node(lit_node))
        return;
    if (lit_node == node)
        return;
    if (hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint let_node = INVALID;
    uint decl_token = INVALID;
    if (!aggregate_lit_let_decl(lit_node, let_node, decl_token))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint field_index = struct_init_field_ordinal_by_node[node];
    uint value_node = hir_struct_lit_field_value_node[node];
    uint expr_len = 0u;
    if (field_index == INVALID ||
        !valid_node(value_node) ||
        !expr_simple_len(value_node, expr_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint address = aggregate_data_base() + (agg_local_base_slots(decl_token) + field_index) * 4u;
    uint len = 1u + i32_sleb_len(address) + expr_len + 3u;
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_AGG_FIELD_STORE_I32, address, value_node, token));
}

void account_assign_index(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return;
    }

    uint rhs_node = stmt_record_slot(node, 2u);
    rhs_node = resolve_expr_node(rhs_node);
    if (!valid_node(rhs_node) || expr_form(rhs_node) != HIR_EXPR_INDEX)
        return;

    uint target_len = 0u;
    uint rhs_len = 0u;
    uint target = stmt_record_slot(node, 1u);
    uint op = stmt_record_slot(node, 3u);
    if (!assign_op_supported(op) ||
        !local_decl_token_for_name_expr(target, target_len) ||
        !index_expr_len(rhs_node, rhs_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint len = op == ASSIGN_OP_SET
                   ? rhs_len + local_set_len(target_len)
                   : local_get_len(target_len) + rhs_len + 1u + local_set_len(target_len);
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(
            op == ASSIGN_OP_SET
                ? BODY_FRAGMENT_ASSIGN_INDEX_I32
                : BODY_FRAGMENT_ASSIGN_COMPOUND_INDEX_I32,
            target_len,
            rhs_node,
            op));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;

    uint token = hir_token_pos[node];
    if ((parser_feature_flags[0u] & PARSER_FEATURE_ARRAYS) != 0u)
    {
        account_let_array(node, owner_fn, token);
        account_array_element(node, owner_fn, token);
    }
    account_assign_index(node, owner_fn, token);
}
