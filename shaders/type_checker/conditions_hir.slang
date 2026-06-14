// HIR condition validation.
//
// This pass consumes parser-owned statement records and attributed expression
// records. It intentionally handles simple single-value conditions here and
// leaves compound expressions to dedicated expression-attribution passes rather
// than scanning condition token ranges.

import generated_parse_production_ids;
import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_nearest_stmt_node;
StructuredBuffer<uint> hir_nearest_block_node;
StructuredBuffer<uint> hir_nearest_fn_node;
StructuredBuffer<uint> hir_match_payload_owner_arm;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_arg_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_syntax_token;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> hir_method_owner_node;
StructuredBuffer<uint> hir_method_name_token;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> generic_decl_owner_by_node;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint INTRINSIC_NONE = 0u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TK_LT = 12u;
static const uint TK_GENERIC_PARAM_LT = 133u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_INVALID_ARRAY_RETURN = 9u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint ERR_TRAIT_BOUND_UNSATISFIED = 13u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;

static const uint HIR_FILE = 1u;
static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_STMT = 7u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;

static const uint HIR_TYPE_FORM_ARRAY = 2u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
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

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint MAX_PATH_SEGMENTS = 9u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint TYPE_LEN_NONE = 0u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
static const uint PREDICATE_STATUS_INVALID_ARG = 4u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_BOUND_ARITY_MISMATCH = 13u;
static const uint PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE = 14u;
static const uint PREDICATE_STATUS_INVALID_IMPL_ARG = 15u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND = 18u;
static const uint PREDICATE_STATUS_OVERLAPPING_IMPL = 19u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH = 25u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW = 27u;
static const uint PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG = 28u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

static const uint TK_GT = 13u;
static const uint TK_COLON = 38u;
static const uint TK_PATH_COLON = 114u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
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
    return path_i != INVALID && path_i < active_path_count();
}

uint token_kind(uint token_i)
{
    return token_i < gParams.n_tokens ? token_words[token_i].kind : 0u;
}

bool type_arg_close(uint kind)
{
    return kind == TK_GT || kind == TK_PATH_TYPE_ARG_GT || kind == TK_TYPE_ARG_GT;
}

bool type_arg_open(uint kind)
{
    return kind == TK_LT || kind == TK_PATH_TYPE_ARG_LT || kind == TK_TYPE_ARG_LT;
}

bool path_colon(uint kind)
{
    return kind == TK_COLON || kind == TK_PATH_COLON;
}

bool bound_type_identifier_token(uint token_i)
{
    return valid_token(token_i) && token_words[token_i].kind == TK_BOUND_TYPE_IDENT;
}

bool qualified_call_callee_leaf_token(uint token_i)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        if (hir_kind[node] != HIR_CALL_EXPR)
            continue;

        uint callee = hir_call_callee_node[node];
        if (!valid_node(callee))
            continue;

        uint start = hir_token_pos[callee];
        uint end = hir_token_end[callee];
        if (valid_token(start) && end != INVALID && token_i > start && token_i < end)
            return true;
    }
    return false;
}

bool token_inside_function_body(uint node, uint token_i)
{
    uint fn_node = valid_node(node) ? hir_nearest_fn_node[node] : INVALID;
    if (!valid_node(fn_node))
        return true;

    uint block_node = hir_nearest_block_node[node];
    if (!valid_node(block_node) || hir_kind[block_node] != HIR_BLOCK)
        return false;
    if (hir_nearest_fn_node[block_node] != fn_node)
        return false;

    uint block_start = hir_token_pos[block_node];
    uint block_end = hir_token_end[block_node];
    return valid_token(block_start) && block_end != INVALID &&
           token_i >= block_start && token_i < block_end;
}

uint condition_parent_record(uint node)
{
    return parent[node];
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_intrinsic_name(uint token_i)
{
    return valid_token(token_i) && call_intrinsic_tag[token_i] != INTRINSIC_NONE;
}

uint visible_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint ty = visible_type[token_i];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token_i];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token_i];
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
}

bool read_decl_type_ref(uint token_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token_i))
        return false;

    uint return_token = call_return_type_token[token_i];
    if (valid_token(return_token))
    {
        tag = decl_type_ref_tag[return_token];
        payload = decl_type_ref_payload[return_token];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    uint ref_token = token_i;
    uint decl = visible_decl[token_i];
    if (valid_token(decl))
        ref_token = decl;

    tag = decl_type_ref_tag[ref_token];
    payload = decl_type_ref_payload[ref_token];
    if (tag != TYPE_REF_INVALID)
        return true;

    if (ref_token != token_i)
    {
        tag = decl_type_ref_tag[token_i];
        payload = decl_type_ref_payload[token_i];
    }
    return tag != TYPE_REF_INVALID;
}

bool same_generic_type_param_ref(uint lhs_payload, uint rhs_payload)
{
    uint lhs_slot = valid_token(lhs_payload) ? type_generic_param_slot_by_token[lhs_payload] : INVALID;
    uint rhs_slot = valid_token(rhs_payload) ? type_generic_param_slot_by_token[rhs_payload] : INVALID;
    return lhs_slot != INVALID && lhs_slot == rhs_slot;
}

bool same_const_len_ref(uint lhs_payload, uint rhs_payload)
{
    uint lhs_slot = valid_token(lhs_payload) ? type_const_param_slot_by_token[lhs_payload] : INVALID;
    uint rhs_slot = valid_token(rhs_payload) ? type_const_param_slot_by_token[rhs_payload] : INVALID;
    return lhs_slot != INVALID && lhs_slot == rhs_slot;
}

bool same_leaf_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag != rhs_tag)
        return false;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM)
        return same_generic_type_param_ref(lhs_payload, rhs_payload);
    return lhs_payload == rhs_payload;
}

bool same_instance_len(uint lhs, uint rhs)
{
    uint lhs_kind = type_instance_len_kind[lhs];
    uint rhs_kind = type_instance_len_kind[rhs];
    if (lhs_kind != rhs_kind)
        return false;
    if (lhs_kind == TYPE_LEN_NONE)
        return true;
    if (lhs_kind == TYPE_LEN_CONST_PARAM)
        return same_const_len_ref(type_instance_len_payload[lhs], type_instance_len_payload[rhs]);
    return type_instance_len_payload[lhs] == type_instance_len_payload[rhs];
}

bool same_type_instance_ref(uint lhs, uint rhs)
{
    if (lhs == rhs)
        return true;
    if (!valid_token(lhs) || !valid_token(rhs))
        return false;

    uint lhs_kind = type_instance_kind[lhs];
    uint rhs_kind = type_instance_kind[rhs];
    if (lhs_kind != rhs_kind)
        return false;

    if (lhs_kind == TYPE_INSTANCE_ARRAY || lhs_kind == TYPE_INSTANCE_SLICE)
    {
        if (!same_leaf_type_ref(
                type_instance_elem_ref_tag[lhs],
                type_instance_elem_ref_payload[lhs],
                type_instance_elem_ref_tag[rhs],
                type_instance_elem_ref_payload[rhs]))
            return false;
        return lhs_kind != TYPE_INSTANCE_ARRAY || same_instance_len(lhs, rhs);
    }

    if (lhs_kind != TYPE_INSTANCE_NAMED)
        return false;

    uint lhs_decl = type_instance_decl_token[lhs];
    uint rhs_decl = type_instance_decl_token[rhs];
    if (valid_token(lhs_decl) || valid_token(rhs_decl))
    {
        if (!valid_token(lhs_decl) || lhs_decl != rhs_decl)
            return false;
    }

    uint lhs_count = type_instance_arg_count[lhs];
    uint rhs_count = type_instance_arg_count[rhs];
    if (lhs_count != rhs_count)
        return false;
    if (lhs_count == 0u)
        return true;
    if (lhs_count > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint lhs_start = type_instance_arg_start[lhs];
    uint rhs_start = type_instance_arg_start[rhs];
    if (lhs_start == INVALID || rhs_start == INVALID)
        return false;

    [loop]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        if (slot >= lhs_count)
            break;
        uint lhs_arg = lhs_start + slot;
        uint rhs_arg = rhs_start + slot;
        if (!same_leaf_type_ref(
                type_instance_arg_ref_tag[lhs_arg],
                type_instance_arg_ref_payload[lhs_arg],
                type_instance_arg_ref_tag[rhs_arg],
                type_instance_arg_ref_payload[rhs_arg]))
            return false;
    }
    return true;
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag != rhs_tag)
        return false;
    if (lhs_tag == TYPE_REF_INSTANCE)
        return same_type_instance_ref(lhs_payload, rhs_payload);
    return same_leaf_type_ref(lhs_tag, lhs_payload, rhs_tag, rhs_payload);
}

bool aggregate_type_code_for_ref_check(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE ||
           (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE);
}

bool aggregate_type_ref_mismatch(uint expected_token, uint actual_token)
{
    uint actual_call_ty = valid_token(actual_token) ? call_return_type[actual_token] : TY_UNKNOWN;
    if (actual_call_ty != TY_UNKNOWN && !aggregate_type_code_for_ref_check(actual_call_ty))
        return false;
    uint actual_visible_ty = visible_type_for_token(actual_token);
    if (actual_visible_ty != TY_UNKNOWN && !aggregate_type_code_for_ref_check(actual_visible_ty))
        return false;

    uint expected_tag = TYPE_REF_INVALID;
    uint expected_payload = INVALID;
    uint actual_tag = TYPE_REF_INVALID;
    uint actual_payload = INVALID;
    if (!read_decl_type_ref(expected_token, expected_tag, expected_payload) ||
        !read_decl_type_ref(actual_token, actual_tag, actual_payload))
        return false;
    if (expected_tag != TYPE_REF_INSTANCE && actual_tag != TYPE_REF_INSTANCE)
        return false;
    return !same_type_ref(expected_tag, expected_payload, actual_tag, actual_payload);
}

uint direct_name_expr_token(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;
    uint token_i = expr_value_token(node);
    if (!valid_token(token_i))
        token_i = hir_token_pos[node];
    return valid_token(token_i) ? token_i : INVALID;
}

uint value_token_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token_i = expr_value_token(node);
    if (!valid_token(token_i))
        token_i = hir_token_pos[node];
    return valid_token(token_i) ? token_i : INVALID;
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_PATH_EXPR)
    {
        uint path_i = path_id_by_owner_hir[callee_node];
        return valid_path(path_i) ? path_i : INVALID;
    }
    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && hir_kind[child] == HIR_PATH_EXPR)
        {
            uint path_i = path_id_by_owner_hir[child];
            return valid_path(path_i) ? path_i : INVALID;
        }
    }
    return INVALID;
}

uint path_leaf_token(uint path_i)
{
    uint count = valid_path(path_i) ? min(path_segment_count[path_i], MAX_PATH_SEGMENTS) : 0u;
    if (count == 0u)
        return INVALID;
    uint slot = path_segment_base[path_i] + count - 1u;
    return slot < gParams.n_tokens * MAX_PATH_SEGMENTS ? path_segment_token[slot] : INVALID;
}

uint token_after_type_args(uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;

    uint cursor = token_i + 1u;
    if (!valid_token(cursor) || !type_arg_open(token_kind(cursor)))
        return cursor;

    cursor += 1u;
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 64u && valid_token(cursor); guard += 1u)
    {
        uint kind = token_kind(cursor);
        if (type_arg_open(kind))
            depth += 1u;
        else if (type_arg_close(kind))
        {
            if (depth == 0u)
                return cursor + 1u;
            depth -= 1u;
        }
        cursor += 1u;
    }
    return INVALID;
}

uint associated_method_token_after_receiver(uint receiver_token)
{
    uint cursor = token_after_type_args(receiver_token);
    if (!valid_token(cursor + 2u))
        return INVALID;
    if (!path_colon(token_kind(cursor)) || !path_colon(token_kind(cursor + 1u)))
        return INVALID;
    return cursor + 2u;
}

uint associated_callee_method_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint path_i = path_id_for_callee_node(callee_node);
    if (!valid_path(path_i))
        return INVALID;
    uint method_token = associated_method_token_after_receiver(path_leaf_token(path_i));
    return valid_token(method_token) ? method_token : INVALID;
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

bool call_has_array_argument(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    [loop]
    for (uint ordinal = 0u; ordinal < PARAM_CACHE_STRIDE; ordinal += 1u)
    {
        uint node = call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
        if (!valid_node(node))
            continue;
        uint value_token = INVALID;
        uint ty = first_value_type_from_node(node, value_token);
        if (is_array_type(ty))
            return true;
    }
    return false;
}

bool direct_unsupported_symbolic_array_call(uint expr_node, uint actual)
{
    if (!is_generic_type(actual))
        return false;

    uint call_node = resolve_expr(expr_node);
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           direct_node_type(call_node) == actual &&
           call_has_array_argument(call_node);
}

bool direct_bounded_symbolic_array_call(uint expr_node, uint actual)
{
    if (actual != TY_ARRAY_BASE + TY_UNKNOWN)
        return false;

    uint call_node = resolve_expr(expr_node);
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           direct_node_type(call_node) == actual &&
           call_has_array_argument(call_node);
}

bool decl_initializer_context_is_array(uint node)
{
    uint type_node = hir_stmt_record[stmt_slot(node, 3u)];
    return valid_node(type_node) &&
           hir_kind[type_node] == HIR_TYPE &&
           hir_type_form[type_node] == HIR_TYPE_FORM_ARRAY;
}

bool parser_published_match_payload(uint node)
{
    return valid_node(node) && valid_node(hir_match_payload_owner_arm[node]);
}

bool parser_published_match_pattern(uint node)
{
    if (!valid_node(node))
        return false;

    uint prod = node_kind[node];
    return prod == PROD_PATTERN_IDENT ||
           prod == PROD_PATTERN_PLAIN ||
           prod == PROD_PATTERN_TUPLE;
}

bool parser_published_type_syntax(uint node, uint token_i)
{
    uint owner = condition_parent_record(node);
    return (valid_node(owner) && hir_kind[owner] == HIR_TYPE) ||
           (valid_token(token_i) && type_expr_ref_tag[token_i] != TYPE_REF_INVALID);
}

uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_INT)
        return TY_INT;
    if (prod == PROD_TRUE || prod == PROD_FALSE)
        return TY_BOOL;
    if (prod == PROD_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_STRING)
        return TY_STRING;
    if (prod == PROD_CHAR)
        return TY_CHAR;
    return TY_UNKNOWN;
}

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = scalar_type_for_literal_prod(node_kind[node]);
    if (lit != TY_UNKNOWN)
        return lit;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint visible = visible_type_for_token(value_token_for_node(node));
        return visible;
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        if (!valid_token(member_token))
            return TY_UNKNOWN;
        return visible_type_for_token(member_token);
    }

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR || node_kind[node] == PROD_STRUCT_LIT)
    {
        uint head_node = hir_struct_lit_head_node[node];
        if (!valid_node(head_node))
            return TY_UNKNOWN;
        uint head_token = hir_token_pos[head_node];
        return visible_type_for_token(head_token);
    }

    if (hir_kind[node] == HIR_INDEX_EXPR)
        return call_return_type[token_i];

    if (hir_kind[node] == HIR_MATCH_EXPR)
        return call_return_type[token_i];

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint call_ty = call_return_type[token_i];
        if (call_ty != TY_UNKNOWN)
            return call_ty;

        uint callee_node = hir_call_callee_node[node];
        if (!valid_node(callee_node))
            return call_return_type[token_i];
        if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
        {
            uint member_token = hir_member_name_token[callee_node];
            return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
        }
        uint associated_method = associated_callee_method_token_for_call(node);
        if (valid_token(associated_method))
        {
            uint associated_ty = call_return_type[associated_method];
            if (associated_ty != TY_UNKNOWN && associated_ty != TY_VOID)
                return associated_ty;
            uint fn_token = call_fn_index[associated_method];
            if (valid_token(fn_token))
            {
                associated_ty = call_return_type[fn_token];
                if (associated_ty != TY_UNKNOWN)
                    return associated_ty;
            }
        }
        uint callee_token = value_token_for_node(callee_node);
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        if (!valid_token(token_i))
            return TY_UNKNOWN;

        return visible_type_for_token(token_i);
    }
    if (form == HIR_EXPR_INDEX)
    {
        uint token_i = hir_token_pos[node];
        return valid_token(token_i) ? call_return_type[token_i] : TY_UNKNOWN;
    }

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

bool expression_result_node(uint node)
{
    if (!valid_node(node))
        return false;
    return hir_kind[node] == HIR_CALL_EXPR ||
           hir_kind[node] == HIR_MEMBER_EXPR ||
           hir_kind[node] == HIR_INDEX_EXPR ||
           hir_kind[node] == HIR_MATCH_EXPR ||
           hir_kind[node] == HIR_STRUCT_LITERAL_EXPR ||
           node_kind[node] == PROD_STRUCT_LIT;
}

uint expression_result_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_node = hir_call_callee_node[node];
        if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
            return hir_member_name_token[callee_node];
        return value_token_for_node(callee_node);
    }
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return hir_member_name_token[node];
    return hir_token_pos[node];
}

uint preferred_result_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    uint node = resolve_expr(root);
    if (!expression_result_node(node))
        return TY_UNKNOWN;

    uint ty = direct_node_type(node);
    if (ty == TY_UNKNOWN)
        return TY_UNKNOWN;

    uint token_i = expression_result_token(node);
    value_token = valid_token(token_i) ? token_i : INVALID;
    return ty;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint resolved = resolve_expr(root);
    uint record_ty = direct_expr_record_type(root);
    if (record_ty != TY_UNKNOWN)
    {
        uint record_node = resolve_expr(root);
        value_token = valid_node(record_node) ? hir_token_pos[record_node] : hir_token_pos[root];
        return record_ty;
    }

    if (expression_result_node(resolved))
    {
        uint root_ty = direct_node_type(resolved);
        if (root_ty != TY_UNKNOWN)
        {
            value_token = expression_result_token(resolved);
            return root_ty;
        }
    }

    uint result_ty = preferred_result_type_from_node(root, value_token);
    if (result_ty != TY_UNKNOWN)
        return result_ty;

    return TY_UNKNOWN;
}

bool struct_literal_node(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR ||
            node_kind[node] == PROD_STRUCT_LIT ||
            valid_node(hir_struct_lit_head_node[node]));
}

uint direct_struct_literal_node(uint node)
{
    if (struct_literal_node(node))
        return node;

    if (!valid_node(node))
        return INVALID;

    uint head = first_child[node];
    if (!valid_node(head))
        return INVALID;

    uint literal = next_sibling[head];
    return struct_literal_node(literal) && hir_struct_lit_head_node[literal] == head ?
        literal :
        INVALID;
}

uint first_struct_literal_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint node = direct_struct_literal_node(resolve_expr(root));
    if (!valid_node(node))
        node = direct_struct_literal_node(root);
    if (valid_node(node))
    {
        uint ty = direct_node_type(node);
        if (ty != TY_UNKNOWN)
        {
            value_token = hir_token_pos[node];
            return ty;
        }
    }
    return TY_UNKNOWN;
}

bool contextual_aggregate_literal_node(uint node, uint context_node)
{
    if (!valid_node(node) || !valid_node(context_node))
        return false;

    if (hir_kind[node] == HIR_ARRAY_EXPR &&
        hir_array_lit_context_stmt_node[node] == context_node)
        return true;

    uint struct_lit = direct_struct_literal_node(node);
    if (valid_node(struct_lit) &&
        hir_struct_lit_context_stmt_node[struct_lit] == context_node)
        return true;

    return false;
}

bool direct_contextual_aggregate_literal_node(uint context_node, uint root)
{
    if (!valid_node(context_node))
        return false;

    uint node = resolve_expr(root);
    if (!valid_node(node))
        return false;

    if (contextual_aggregate_literal_node(node, context_node))
        return true;

    if (node != root && contextual_aggregate_literal_node(root, context_node))
        return true;

    return false;
}

uint direct_array_literal_node(uint root)
{
    if (!valid_node(root))
        return INVALID;

    uint node = resolve_expr(root);
    return valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR ? node : INVALID;
}

bool has_contextual_aggregate_literal_node(uint context_node, uint root)
{
    return direct_contextual_aggregate_literal_node(context_node, root);
}

bool is_contextual_aggregate_type(uint ty)
{
    return is_array_type(ty) ||
           (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE);
}

uint single_value_condition_type(uint expr_node)
{
    if (!valid_node(expr_node))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(expr_node);
    if (record_ty != TY_UNKNOWN)
        return record_ty;

    uint node = resolve_expr(expr_node);
    if (!valid_node(node) || hir_kind[node] == HIR_CALL_EXPR || hir_kind[node] == HIR_MEMBER_EXPR)
        return TY_UNKNOWN;

    return direct_node_type(node);
}

void validate_decl_initializer_node(uint node)
{
    uint stmt_kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (stmt_kind != STMT_RECORD_KIND_LET && stmt_kind != STMT_RECORD_KIND_CONST)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    if (!valid_token(decl_token))
        return;

    uint expected = visible_type_for_token(decl_token);
    if (expected == TY_UNKNOWN)
    {
        uint actual_token = direct_name_expr_token(hir_stmt_record[stmt_slot(node, 2u)]);
        if (aggregate_type_ref_mismatch(decl_token, actual_token))
            record_error(actual_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint value_token = INVALID;
    uint actual = TY_UNKNOWN;
    if (is_contextual_aggregate_type(expected) &&
        has_contextual_aggregate_literal_node(node, expr_node))
        actual = expected;
    else
        actual = first_struct_literal_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        actual = first_value_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        return;

    if (decl_initializer_context_is_array(node) &&
        direct_bounded_symbolic_array_call(expr_node, actual))
        return;

    if (direct_unsupported_symbolic_array_call(expr_node, actual))
    {
        uint error_token = valid_token(value_token) ? value_token : decl_token;
        record_error(error_token, ERR_ASSIGN_MISMATCH, actual);
    }

    if (actual == expected && aggregate_type_ref_mismatch(decl_token, value_token))
    {
        uint error_token = valid_token(value_token) ? value_token : decl_token;
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
        return;
    }

    if (!assignable(expected, actual))
    {
        uint error_token = valid_token(value_token) ? value_token : decl_token;
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
    }
}

void validate_assignment_node(uint node)
{
    if (hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_ASSIGN)
        return;

    uint target_node = hir_stmt_record[stmt_slot(node, 1u)];
    uint target_token = INVALID;
    uint expected = first_value_type_from_node(target_node, target_token);
    if (expected == TY_UNKNOWN)
    {
        target_token = direct_name_expr_token(target_node);
        uint actual_token = direct_name_expr_token(hir_stmt_record[stmt_slot(node, 2u)]);
        if (aggregate_type_ref_mismatch(target_token, actual_token))
            record_error(actual_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint value_token = INVALID;
    uint actual = TY_UNKNOWN;
    if (is_contextual_aggregate_type(expected) &&
        has_contextual_aggregate_literal_node(node, expr_node))
        actual = expected;
    else if (is_array_type(expected))
    {
        uint array_node = direct_array_literal_node(expr_node);
        if (valid_node(array_node))
        {
            uint error_token = hir_token_pos[array_node];
            if (!valid_token(error_token))
                error_token = valid_token(target_token) ? target_token : hir_token_pos[node];
            record_error(error_token, ERR_ASSIGN_MISMATCH, expected);
            return;
        }
    }
    else
        actual = first_struct_literal_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        actual = first_value_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        return;

    if (actual == expected && aggregate_type_ref_mismatch(target_token, value_token))
    {
        uint error_token = valid_token(value_token) ? value_token : target_token;
        if (!valid_token(error_token))
            error_token = hir_token_pos[node];
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
        return;
    }

    if (!assignable(expected, actual))
    {
        uint error_token = valid_token(value_token) ? value_token : target_token;
        if (!valid_token(error_token))
            error_token = hir_token_pos[node];
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
    }
}

uint enclosing_function_return_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint encoded_fn = enclosing_fn[token_i];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    return valid_token(fn_token) ? call_return_type[fn_token] : TY_UNKNOWN;
}

uint enclosing_function_return_type_token_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;

    uint encoded_fn = enclosing_fn[token_i];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    return valid_token(fn_token) ? call_return_type_token[fn_token] : INVALID;
}

void validate_return_node(uint node)
{
    if (hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[node];
    uint expected = enclosing_function_return_type_for_token(return_token);

    uint expr_node = hir_stmt_record[stmt_slot(node, 1u)];
    uint value_token = INVALID;
    uint actual = TY_UNKNOWN;
    if (!valid_node(expr_node))
    {
        uint explicit_return_type = enclosing_function_return_type_token_for_token(return_token);
        if (valid_token(explicit_return_type) && expected != TY_VOID && expected != TY_UNKNOWN)
        {
            uint error_token = valid_token(return_token) ? return_token : 0u;
            record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + TY_VOID);
        }
        return;
    }
    if (is_array_type(expected))
    {
        if (valid_token(return_token) && call_return_type[return_token] == ARRAY_RETURN_OK)
            actual = expected;
        else
        {
            uint error_token = valid_token(return_token) ? return_token : 0u;
            record_error(error_token, ERR_INVALID_ARRAY_RETURN, expected);
            return;
        }
    }
    else if (is_contextual_aggregate_type(expected) &&
             has_contextual_aggregate_literal_node(node, expr_node))
        actual = expected;
    else
        actual = first_struct_literal_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        actual = first_value_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        return;

    uint error_token = valid_token(value_token) ? value_token : return_token;
    if (direct_unsupported_symbolic_array_call(expr_node, actual))
        record_error(error_token, ERR_ASSIGN_MISMATCH, actual);

    if (expected == TY_UNKNOWN)
        return;

    if (!assignable(expected, actual))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
    }
}

void validate_value_path_status_node(uint node)
{
    if (hir_kind[node] != HIR_NAME_EXPR)
        return;
    if (expr_form(node) != HIR_EXPR_NAME)
        return;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return;
    if (predicate_syntax_token[token_i] != 0u)
        return;
    if (!token_inside_function_body(node, token_i))
        return;
    uint nearest_stmt = hir_nearest_stmt_node[node];
    if (!valid_node(nearest_stmt))
        return;
    uint stmt_start = hir_token_pos[nearest_stmt];
    uint stmt_end = hir_token_end[nearest_stmt];
    if (!valid_token(stmt_start) || stmt_end == INVALID ||
        token_i < stmt_start || token_i >= stmt_end)
        return;
    if (bound_type_identifier_token(token_i))
        return;
    // Intrinsic call heads are resolved by the call-record pass; call arguments
    // remain ordinary value expressions and are validated by their own HIR rows.
    if (is_intrinsic_name(token_i))
        return;
    if (parser_published_match_payload(node))
        return;
    if (parser_published_match_pattern(node))
        return;
    if (parser_published_type_syntax(node, token_i))
        return;
    if (method_call_name_id[token_i] != INVALID)
        return;
    if (qualified_call_callee_leaf_token(token_i))
        return;

    bool resolved_by_decl = valid_token(visible_decl[token_i]);
    bool resolved_call =
        resolved_by_decl ||
        valid_token(call_fn_index[token_i]) ||
        call_return_type[token_i] != TY_UNKNOWN;
    if (resolved_call)
        return;

    uint path_status = module_value_path_status[token_i];
    if (path_status != PATH_RESOLVE_STATUS_INVALID &&
        path_status != PATH_RESOLVE_STATUS_OK)
    {
        record_error(token_i, ERR_UNRESOLVED_IDENT, path_status);
        return;
    }

    uint path_node = first_child[node];
    bool valid_path_node = path_node != INVALID && path_node < active_hir_node_count() &&
                           hir_kind[path_node] == HIR_PATH_EXPR;
    uint end_i = valid_path_node
                     ? hir_token_end[path_node]
                     : hir_token_end[node];
    bool one_segment = end_i != INVALID && end_i == token_i + 1u;
    uint sibling = next_sibling[node];
    bool valid_sibling = sibling != INVALID && sibling < active_hir_node_count();
    uint path_sibling = valid_path_node ? next_sibling[path_node] : INVALID;
    bool valid_path_sibling =
        path_sibling != INVALID && path_sibling < active_hir_node_count();
    bool call_head = (valid_sibling && hir_kind[sibling] == HIR_CALL_EXPR) ||
                     (valid_path_sibling && hir_kind[path_sibling] == HIR_CALL_EXPR);
    bool postfix_head =
        (valid_sibling &&
         (hir_kind[sibling] == HIR_INDEX_EXPR ||
          hir_kind[sibling] == HIR_MEMBER_EXPR ||
          hir_kind[sibling] == HIR_STRUCT_LITERAL_EXPR)) ||
        (valid_path_sibling &&
         (hir_kind[path_sibling] == HIR_INDEX_EXPR ||
          hir_kind[path_sibling] == HIR_MEMBER_EXPR ||
          hir_kind[path_sibling] == HIR_STRUCT_LITERAL_EXPR));
    if (one_segment && call_head && !resolved_call &&
        visible_type_for_token(token_i) == TY_UNKNOWN)
    {
        record_error(token_i, ERR_UNRESOLVED_IDENT, 0u);
        return;
    }

    if (one_segment && !call_head && !postfix_head && !resolved_by_decl &&
        visible_type_for_token(token_i) == TY_UNKNOWN)
        record_error(token_i, ERR_UNRESOLVED_IDENT, 0u);
}

void validate_if_node(uint node)
{
    if (hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_IF)
        return;

    uint expr_node = hir_stmt_record[stmt_slot(node, 1u)];
    uint ty = single_value_condition_type(expr_node);
    if (ty != TY_UNKNOWN && ty != TY_BOOL)
    {
        uint token_i = valid_node(expr_node) ? hir_token_pos[expr_node] : hir_token_pos[node];
        record_error(token_i, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + ty);
    }
}

void validate_logical_expr_node(uint node)
{
    uint form = expr_form(node);
    if (form != HIR_EXPR_NOT && form != HIR_EXPR_AND && form != HIR_EXPR_OR)
        return;

    uint left = expr_left(node);
    uint left_ty = direct_expr_record_type(left);
    if (left_ty != TY_UNKNOWN && left_ty != TY_BOOL)
    {
        uint token_i = valid_node(left) ? hir_token_pos[left] : hir_token_pos[node];
        record_error(token_i, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + left_ty);
        return;
    }

    if (form == HIR_EXPR_NOT)
        return;

    uint right = expr_right(node);
    uint right_ty = direct_expr_record_type(right);
    if (right_ty != TY_UNKNOWN && right_ty != TY_BOOL)
    {
        uint token_i = valid_node(right) ? hir_token_pos[right] : hir_token_pos[node];
        record_error(token_i, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + right_ty);
    }
}

bool record_method_contract_generic_ref_error(uint node)
{
    uint method_node = hir_nearest_fn_node[node];
    if (!valid_node(method_node) || !method_contract_production(method_node))
        return false;

    uint token_i = method_contract_name_token_from_rows(method_node);
    if (!valid_token(token_i))
        token_i = hir_token_pos[method_node];
    record_error(
        valid_token(token_i) ? token_i : 0u,
        ERR_BAD_HIR,
        PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC);
    return true;
}

void validate_generic_type_ref_node(uint node)
{
    if (hir_kind[node] != HIR_TYPE)
        return;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return;
    if (predicate_syntax_token[token_i] != 0u)
        return;
    if (bound_type_identifier_token(token_i))
        return;

    uint ref_tag = type_expr_ref_tag[token_i];
    if (ref_tag == TYPE_REF_ERROR)
    {
        record_error(token_i, ERR_UNKNOWN_TYPE, type_expr_ref_payload[token_i]);
        return;
    }

    if (ref_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint payload = type_expr_ref_payload[token_i];
        if (!valid_token(payload) ||
            type_generic_param_slot_by_token[payload] == INVALID)
        {
            if (record_method_contract_generic_ref_error(node))
                return;
            record_error(token_i, ERR_UNRESOLVED_IDENT, 0u);
        }
    }

    if (hir_type_form[node] == HIR_TYPE_FORM_ARRAY &&
        type_instance_len_kind[token_i] == TYPE_LEN_CONST_PARAM)
    {
        uint len_token = type_instance_len_payload[token_i];
        if (!valid_token(len_token) ||
            type_const_param_slot_by_token[len_token] == INVALID)
            record_error(token_i, ERR_UNRESOLVED_IDENT, len_token);
    }
}

void validate_unsupported_generic_decl_node(uint node)
{
    uint kind = node_kind[node];
    if (kind != PROD_BOUND_TYPE_IDENT && kind != PROD_BOUND_TYPE_REF)
        return;

    uint status_value = predicate_status[node];
    if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
    {
        uint token_i = hir_token_pos[node];
        if (status_value == PREDICATE_STATUS_INVALID_SUBJECT &&
            valid_token(predicate_subject_token[node]))
        {
            token_i = predicate_subject_token[node];
        }
        if ((status_value == PREDICATE_STATUS_INVALID_ARG ||
             status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
             status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION) &&
            (valid_token(predicate_bound_first_arg_token[node]) ||
             valid_token(predicate_bound_second_arg_token[node])))
        {
            token_i = valid_token(predicate_bound_second_arg_token[node])
                ? predicate_bound_second_arg_token[node]
                : predicate_bound_first_arg_token[node];
        }
        bool unsupported_predicate_row =
            status_value == PREDICATE_STATUS_INVALID_SUBJECT ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
            status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        uint code = unsupported_predicate_row ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_UNKNOWN_TYPE;
        record_error(valid_token(token_i) ? token_i : 0u, code, status_value);
    }
}

void validate_unsupported_trait_node(uint node)
{
    uint prod = node_kind[node];
    if (prod == PROD_IMPL_TRAIT || prod == PROD_IMPL_INHERENT)
    {
        uint status_value = predicate_status[node];
        if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
        {
            uint token_i = hir_token_pos[node];
            bool invalid_method =
                status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
                status_value == PREDICATE_STATUS_INVALID_ARG ||
                status_value == PREDICATE_STATUS_BOUND_NOT_TRAIT ||
                status_value == PREDICATE_STATUS_MISSING_METHOD ||
                status_value == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
                status_value == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
                status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE ||
                status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
                status_value == PREDICATE_STATUS_OVERLAPPING_IMPL ||
                status_value == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
                status_value == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
                status_value == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
                status_value == PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH ||
                status_value == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
            uint code = status_value == PREDICATE_STATUS_INVALID_SUBJECT
                ? ERR_UNRESOLVED_IDENT
                : (invalid_method ? ERR_BAD_HIR : ERR_UNKNOWN_TYPE);
            bool trait_impl_arg_status =
                status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
                status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
            if (trait_impl_arg_status && valid_token(predicate_bound_second_arg_token[node]))
            {
                token_i = predicate_bound_second_arg_token[node];
            }
            else if ((status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
                      status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
                      status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
                      status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
                      status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
                      status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG ||
                      status_value == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
                      status_value == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
                      status_value == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH) &&
                     valid_token(predicate_bound_first_arg_token[node]))
            {
                token_i = predicate_bound_first_arg_token[node];
            }
            record_error(valid_token(token_i) ? token_i : 0u, code, status_value);
        }
    }
}

bool method_contract_production(uint node)
{
    uint prod = node_kind[node];
    return prod == PROD_TRAIT_METHOD ||
           prod == PROD_TRAIT_METHOD_PUB ||
           prod == PROD_IMPL_FN;
}

bool generic_param_decl_node(uint node)
{
    uint prod = node_kind[node];
    return prod == PROD_ENUM_TYPE_PARAMS_SOME ||
           prod == PROD_ENUM_TYPE_PARAM ||
           prod == PROD_ENUM_CONST_PARAM;
}

uint parser_method_signature_status(uint node)
{
    uint flags = hir_method_signature_flags[node];
    if ((flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC;
    if ((flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
    return PREDICATE_STATUS_OK;
}

uint method_contract_name_token_from_rows(uint node)
{
    uint token_i = hir_method_name_token[node];
    if (valid_token(token_i))
        return token_i;

    token_i = predicate_method_contract_name_token[node];
    if (valid_token(token_i))
        return token_i;

    uint start = hir_token_pos[node];
    if (!valid_token(start))
        return INVALID;

    uint prod = node_kind[node];
    if (prod == PROD_TRAIT_METHOD_PUB)
        return start + 2u < gParams.n_tokens ? start + 2u : INVALID;
    if (prod == PROD_TRAIT_METHOD || prod == PROD_IMPL_FN)
        return start + 1u < gParams.n_tokens ? start + 1u : INVALID;
    return INVALID;
}

bool method_name_followed_by_type_params(uint node)
{
    uint name_token = method_contract_name_token_from_rows(node);
    return valid_token(name_token) &&
           name_token + 1u < gParams.n_tokens &&
           (token_words[name_token + 1u].kind == TK_LT ||
            token_words[name_token + 1u].kind == TK_GENERIC_PARAM_LT);
}

uint method_contract_status_from_rows(uint node)
{
    uint status_value = predicate_status[node];
    if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
        return status_value;

    status_value = predicate_method_contract_status[node];
    if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
        return status_value;

    return parser_method_signature_status(node);
}

void validate_unsupported_method_contract_node(uint node)
{
    if (!method_contract_production(node))
        return;

    uint status_value = method_contract_status_from_rows(node);
    if (status_value == PREDICATE_STATUS_OK)
        return;

    uint token_i = predicate_bound_first_arg_token[node];
    if (!valid_token(token_i))
        token_i = method_contract_name_token_from_rows(node);
    if (!valid_token(token_i))
        token_i = hir_token_pos[node];
    record_error(valid_token(token_i) ? token_i : 0u, ERR_BAD_HIR, status_value);
}

void validate_method_level_generic_param_row(uint node)
{
    if (!generic_param_decl_node(node))
        return;

    uint owner = generic_decl_owner_by_node[node];
    if (!valid_node(owner) || !method_contract_production(owner))
        return;

    uint token_i = method_contract_name_token_from_rows(owner);
    if (!valid_token(token_i))
        token_i = hir_token_pos[owner];
    record_error(valid_token(token_i) ? token_i : 0u, ERR_BAD_HIR, PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC);
}

void validate_call_argument_width_node(uint node)
{
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    validate_call_argument_width_node(node);
    validate_if_node(node);
    validate_logical_expr_node(node);
    validate_decl_initializer_node(node);
    validate_assignment_node(node);
    validate_return_node(node);
    validate_value_path_status_node(node);
    validate_generic_type_ref_node(node);
    validate_unsupported_generic_decl_node(node);
    validate_unsupported_trait_node(node);
    validate_unsupported_method_contract_node(node);
    validate_method_level_generic_param_row(node);
}
