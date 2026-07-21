// HIR condition validation.
//
// This pass consumes parser-owned statement records and attributed expression
// records. It intentionally handles simple single-value conditions here and
// leaves compound expressions to dedicated expression-attribution passes rather
// than scanning condition token ranges.

import generated_parse_production_ids;
import fixed.compact_method;
import hir_expr_semantics;
import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gParams;

struct CompactFnPayload { uint a; uint b; uint c; uint d; };
struct CompactMethodSignature
{
    uint first_param_token;
    uint impl_receiver_type;
    uint receiver_mode;
    uint metadata;
};

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
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_nearest_stmt_node;
StructuredBuffer<uint> hir_nearest_block_node;
StructuredBuffer<uint> hir_nearest_fn_node;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_has_array_arg;
StructuredBuffer<uint> call_array_return_arg_instance;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> module_type_path_status;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> module_value_path_call_path_id;
StructuredBuffer<uint> module_value_path_call_leaf;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<CompactFnPayload> compact_hir_payload;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<CompactMethodSignature> compact_method_signatures;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> type_subtree_compare_scan_input;
RWStructuredBuffer<uint> type_subtree_compare_left_root;
RWStructuredBuffer<uint> type_subtree_compare_right_root;
RWStructuredBuffer<uint> type_subtree_compare_error_token;
RWStructuredBuffer<uint> type_subtree_compare_error_detail;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_syntax_token;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_validation_first_error_row;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_validation_detail_token;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> generic_decl_owner_by_node;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint PARSER_FEATURE_TYPE_ARGS = 0x00000001u;
static const uint PARSER_FEATURE_ARRAYS = 0x00000002u;
static const uint PARSER_FEATURE_ENUMS = 0x00000004u;
static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;
static const uint AGGREGATE_FEATURES = PARSER_FEATURE_TYPE_ARGS |
                                       PARSER_FEATURE_ARRAYS |
                                       PARSER_FEATURE_ENUMS |
                                       PARSER_FEATURE_STRUCTS;
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

bool bound_type_identifier_token(uint token_i)
{
    return valid_token(token_i) && token_words[token_i].kind == TK_BOUND_TYPE_IDENT;
}

uint first_bound_arg_token_after_bound(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint bound_token = hir_token_pos[node];
    if (!valid_token(bound_token))
        return INVALID;

    uint candidate = bound_token + 1u;
    if (candidate >= bound_token &&
        valid_token(candidate) &&
        (token_kind(candidate) == TK_LT || token_kind(candidate) == TK_GENERIC_PARAM_LT))
    {
        uint arg_token = candidate + 1u;
        return arg_token >= candidate && valid_token(arg_token) ? arg_token : INVALID;
    }
    if (candidate >= bound_token && bound_type_identifier_token(candidate))
        return candidate;

    candidate = bound_token + 2u;
    if (candidate >= bound_token &&
        valid_token(candidate) &&
        (token_kind(candidate) == TK_LT || token_kind(candidate) == TK_GENERIC_PARAM_LT))
    {
        uint arg_token = candidate + 1u;
        return arg_token >= candidate && valid_token(arg_token) ? arg_token : INVALID;
    }
    if (candidate >= bound_token && bound_type_identifier_token(candidate))
        return candidate;

    candidate = bound_token + 3u;
    return candidate >= bound_token && bound_type_identifier_token(candidate)
        ? candidate
        : INVALID;
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

uint plain_generic_slot(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_GENERIC_BASE
        : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
        : INVALID;
}

uint inferred_generic_call_return_type(uint call_token, uint declared_ret_ty)
{
    if (!valid_token(call_token))
        return TY_UNKNOWN;

    uint slot = plain_generic_slot(declared_ret_ty);
    if (slot != INVALID)
    {
        uint inferred = call_generic_slot_type[call_token * PARAM_CACHE_STRIDE + slot];
        return inferred == INVALID ? TY_UNKNOWN : inferred;
    }

    slot = array_or_slice_generic_slot(declared_ret_ty);
    if (slot != INVALID)
    {
        uint inferred = call_generic_slot_type[call_token * PARAM_CACHE_STRIDE + slot];
        return inferred == INVALID ? TY_UNKNOWN : TY_ARRAY_BASE + inferred;
    }

    return TY_UNKNOWN;
}

uint call_result_type_for_token(uint call_token)
{
    if (!valid_token(call_token))
        return TY_UNKNOWN;

    uint ty = call_return_type[call_token];
    if (ty != TY_UNKNOWN && ty < TY_GENERIC_BASE)
        return ty;

    uint inferred = inferred_generic_call_return_type(call_token, ty);
    if (inferred != TY_UNKNOWN)
        return inferred;

    uint fn_token = call_fn_index[call_token];
    if (valid_token(fn_token))
    {
        inferred = inferred_generic_call_return_type(call_token, call_return_type[fn_token]);
        if (inferred != TY_UNKNOWN)
            return inferred;
    }

    return ty;
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
        tag = type_expr_ref_tag[return_token];
        payload = type_expr_ref_payload[return_token];
        if (tag != TYPE_REF_INVALID)
            return true;

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
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    tag = type_expr_ref_tag[token_i];
    payload = type_expr_ref_payload[token_i];
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

uint instance_arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

uint instance_arg_row_ref_index(uint instance_i, uint ordinal)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint row_ref_i = instance_arg_row_ref_index(instance_i, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint fixed_ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (fixed_ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[fixed_ref_i];
    payload = type_instance_arg_ref_payload[fixed_ref_i];
    return tag != TYPE_REF_INVALID;
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
    else
    {
        uint lhs_external = type_instance_external_canonical[lhs];
        uint rhs_external = type_instance_external_canonical[rhs];
        if (lhs_external == INVALID || lhs_external != rhs_external)
            return false;
    }

    uint lhs_count = type_instance_arg_count[lhs];
    uint rhs_count = type_instance_arg_count[rhs];
    if (lhs_count != rhs_count)
        return false;
    if (lhs_count == 0u)
        return true;

    for (uint slot = 0u; slot < lhs_count; slot += 1u)
    {
        uint lhs_tag;
        uint lhs_payload;
        uint rhs_tag;
        uint rhs_payload;
        if (!instance_arg_ref(lhs, slot, lhs_tag, lhs_payload) ||
            !instance_arg_ref(rhs, slot, rhs_tag, rhs_payload))
            return false;

        if (!same_leaf_type_ref(
                lhs_tag,
                lhs_payload,
                rhs_tag,
                rhs_payload))
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

void clear_aggregate_compare_request(uint node)
{
    if ((gParams.parser_feature_flags & AGGREGATE_FEATURES) == 0u)
        return;
    aggregate_compare_scan_input[node] = 0u;
    aggregate_compare_expected_instance[node] = INVALID;
    aggregate_compare_actual_instance[node] = INVALID;
    aggregate_compare_error_token[node] = INVALID;
    aggregate_compare_error_detail[node] = 0u;
    type_subtree_compare_scan_input[node] = 0u;
    type_subtree_compare_left_root[node] = INVALID;
    type_subtree_compare_right_root[node] = INVALID;
    type_subtree_compare_error_token[node] = INVALID;
    type_subtree_compare_error_detail[node] = 0u;
}

uint aggregate_compare_error_site(
    uint node,
    uint expected_token,
    uint actual_token,
    uint error_token)
{
    if (valid_token(error_token))
        return error_token;
    if (valid_token(actual_token))
        return actual_token;
    if (valid_token(expected_token))
        return expected_token;
    return valid_node(node) && valid_token(hir_token_pos[node]) ? hir_token_pos[node] : 0u;
}

void enqueue_aggregate_compare(
    uint node,
    uint expected_instance,
    uint actual_instance,
    uint expected_token,
    uint actual_token,
    uint error_token,
    uint detail)
{
    if ((gParams.parser_feature_flags & AGGREGATE_FEATURES) == 0u)
        return;
    if (!valid_node(node))
        return;
    aggregate_compare_scan_input[node] = type_instance_arg_count[expected_instance];
    aggregate_compare_expected_instance[node] = expected_instance;
    aggregate_compare_actual_instance[node] = actual_instance;
    aggregate_compare_error_token[node] =
        aggregate_compare_error_site(node, expected_token, actual_token, error_token);
    aggregate_compare_error_detail[node] = detail;
}

bool aggregate_instance_ref_mismatch(
    uint node,
    uint expected_instance,
    uint actual_instance,
    uint expected_token,
    uint actual_token,
    uint error_token,
    uint detail)
{
    if (expected_instance == actual_instance)
        return false;
    if (!valid_token(expected_instance) || !valid_token(actual_instance))
        return true;

    uint expected_kind = type_instance_kind[expected_instance];
    uint actual_kind = type_instance_kind[actual_instance];
    if (expected_kind != actual_kind)
        return true;

    if (expected_kind == TYPE_INSTANCE_ARRAY || expected_kind == TYPE_INSTANCE_SLICE)
        return !same_type_instance_ref(expected_instance, actual_instance);

    if (expected_kind != TYPE_INSTANCE_NAMED)
        return true;

    uint expected_decl = type_instance_decl_token[expected_instance];
    uint actual_decl = type_instance_decl_token[actual_instance];
    if (valid_token(expected_decl) || valid_token(actual_decl))
    {
        if (!valid_token(expected_decl) || expected_decl != actual_decl)
            return true;
    }
    else
    {
        uint expected_external = type_instance_external_canonical[expected_instance];
        uint actual_external = type_instance_external_canonical[actual_instance];
        if (expected_external == INVALID || expected_external != actual_external)
            return true;
    }

    uint expected_count = type_instance_arg_count[expected_instance];
    uint actual_count = type_instance_arg_count[actual_instance];
    if (expected_count != actual_count)
        return true;
    if (expected_count == 0u)
        return false;

    enqueue_aggregate_compare(
        node,
        expected_instance,
        actual_instance,
        expected_token,
        actual_token,
        error_token,
        detail);
    return false;
}

bool aggregate_type_ref_mismatch(
    uint node,
    uint expected_token,
    uint actual_token,
    uint error_token,
    uint detail)
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
    bool has_expected_ref =
        read_decl_type_ref(expected_token, expected_tag, expected_payload);
    bool has_actual_ref =
        read_decl_type_ref(actual_token, actual_tag, actual_payload);
    if (!has_expected_ref || !has_actual_ref)
        return false;
    if (expected_tag != TYPE_REF_INSTANCE && actual_tag != TYPE_REF_INSTANCE)
        return false;
    if (expected_tag != actual_tag)
        return true;
    if (expected_tag != TYPE_REF_INSTANCE)
        return !same_leaf_type_ref(expected_tag, expected_payload, actual_tag, actual_payload);

    return aggregate_instance_ref_mismatch(
        node,
        expected_payload,
        actual_payload,
        expected_token,
        actual_token,
        error_token,
        detail);
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

uint call_node_for_expr_anchor(uint node)
{
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_CALL_EXPR)
        return node;
    uint call_node = hir_call_parent_by_callee[node];
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR
        ? call_node
        : INVALID;
}

uint call_node_for_expr(uint root)
{
    if (!valid_node(root))
        return INVALID;

    uint node = resolve_expr(root);
    uint call_node = call_node_for_expr_anchor(node);
    if (valid_node(call_node))
        return call_node;

    return node != root ? call_node_for_expr_anchor(root) : INVALID;
}

uint resolved_array_call_result_instance(uint expr_node)
{
    uint call_node = call_node_for_expr(expr_node);
    if (!valid_node(call_node))
        return INVALID;
    uint instance_i = call_array_return_arg_instance[call_node];
    return valid_token(instance_i) ? instance_i : INVALID;
}

bool aggregate_expr_type_ref_mismatch(
    uint node,
    uint expected_token,
    uint expr_node,
    uint actual_token,
    uint error_token,
    uint detail)
{
    uint resolved_instance = resolved_array_call_result_instance(expr_node);
    if (resolved_instance == INVALID)
    {
        return aggregate_type_ref_mismatch(
            node,
            expected_token,
            actual_token,
            error_token,
            detail);
    }

    // Array-call inference has already produced the concrete semantic result
    // instance. Compare against that result rather than the callee's symbolic
    // source declaration (for example `[T; N]`).
    uint expected_tag = TYPE_REF_INVALID;
    uint expected_payload = INVALID;
    if (!read_decl_type_ref(expected_token, expected_tag, expected_payload))
        return false;
    if (expected_tag != TYPE_REF_INSTANCE)
        return true;

    return aggregate_instance_ref_mismatch(
        node,
        expected_payload,
        resolved_instance,
        expected_token,
        actual_token,
        error_token,
        detail);
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;

    // path_id_by_owner_hir is keyed by dense compact-HIR ids. This validator
    // still walks legacy raw call records, so crossing that table directly
    // would mix index domains. Call discovery publishes the same semantic path
    // relation by each distinct source anchor used by the call, owner, and leaf.
    uint token = value_token_for_node(callee_node);
    if (!valid_token(token))
        token = hir_token_pos[callee_node];
    uint path_i = valid_token(token) ? module_value_path_call_path_id[token] : INVALID;
    if (valid_path(path_i))
        return path_i;

    uint child = first_child[callee_node];
    if (valid_node(child))
    {
        token = value_token_for_node(child);
        if (!valid_token(token))
            token = hir_token_pos[child];
        path_i = valid_token(token) ? module_value_path_call_path_id[token] : INVALID;
        if (valid_path(path_i))
            return path_i;
    }
    return INVALID;
}

uint path_leaf_token(uint path_i)
{
    uint count = valid_path(path_i) ? path_segment_count[path_i] : 0u;
    if (count == 0u)
        return INVALID;
    uint slot = path_segment_base[path_i] + count - 1u;
    return slot < gParams.n_tokens ? path_segment_token[slot] : INVALID;
}

uint associated_callee_method_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint path_i = path_id_for_callee_node(callee_node);
    if (valid_path(path_i))
    {
        uint owner_token = path_owner_token[path_i];
        uint method_token = valid_token(owner_token)
            ? module_value_path_associated_method_token[owner_token]
            : INVALID;
        if (valid_token(method_token))
            return method_token;
        uint receiver_token = path_leaf_token(path_i);
        method_token = valid_token(receiver_token)
            ? module_value_path_associated_method_token[receiver_token]
            : INVALID;
        return valid_token(method_token) ? method_token : receiver_token;
    }

    uint call_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    uint method_token = valid_token(call_token)
        ? module_value_path_associated_method_token[call_token]
        : INVALID;
    if (valid_token(method_token))
        return method_token;
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    return valid_token(callee_token) ? module_value_path_associated_method_token[callee_token] : INVALID;
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
    return valid_node(call_node) && call_has_array_arg[call_node] != 0u;
}

bool direct_unsupported_symbolic_array_call(uint expr_node, uint actual)
{
    if (!is_generic_type(actual))
        return false;

    uint call_node = call_node_for_expr(expr_node);
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           direct_node_type(call_node) == actual &&
           call_has_array_argument(call_node);
}

bool direct_bounded_symbolic_array_call(uint expr_node, uint actual)
{
    if (actual != TY_ARRAY_BASE + TY_UNKNOWN)
        return false;

    uint call_node = call_node_for_expr(expr_node);
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           direct_node_type(call_node) == actual &&
           call_has_array_argument(call_node);
}

bool resolved_call_token_has_unknown_result(uint token_i)
{
    return valid_token(token_i) &&
           valid_token(call_fn_index[token_i]) &&
           call_result_type_for_token(token_i) == TY_UNKNOWN;
}

bool resolved_call_token_has_known_result(uint token_i)
{
    return valid_token(token_i) &&
           valid_token(call_fn_index[token_i]) &&
           call_result_type_for_token(token_i) != TY_UNKNOWN;
}

void observe_resolved_call_token_result(
    uint token_i,
    inout bool saw_unknown,
    inout bool saw_known)
{
    if (resolved_call_token_has_known_result(token_i))
        saw_known = true;
    else if (resolved_call_token_has_unknown_result(token_i))
        saw_unknown = true;
}

bool resolved_call_expr_has_unknown_result(uint expr_node)
{
    uint call_node = call_node_for_expr(expr_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    bool saw_unknown = false;
    bool saw_known = false;
    observe_resolved_call_token_result(hir_token_pos[call_node], saw_unknown, saw_known);

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return saw_unknown && !saw_known;

    uint path_i = path_id_for_callee_node(callee_node);
    if (valid_path(path_i))
    {
        uint owner_token = path_owner_token[path_i];
        observe_resolved_call_token_result(owner_token, saw_unknown, saw_known);
        uint leaf_token = path_leaf_token(path_i);
        if (leaf_token != owner_token)
            observe_resolved_call_token_result(leaf_token, saw_unknown, saw_known);
    }

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
        observe_resolved_call_token_result(hir_member_name_token[callee_node], saw_unknown, saw_known);

    observe_resolved_call_token_result(
        associated_callee_method_token_for_call(call_node),
        saw_unknown,
        saw_known);

    observe_resolved_call_token_result(value_token_for_node(callee_node), saw_unknown, saw_known);
    return saw_unknown && !saw_known;
}

void observe_call_token_resolution(uint token_i, inout bool resolved)
{
    if (!valid_token(token_i))
        return;
    if (valid_token(call_fn_index[token_i]) ||
        call_result_type_for_token(token_i) != TY_UNKNOWN ||
        call_intrinsic_tag[token_i] != INTRINSIC_NONE ||
        method_call_name_id[token_i] != INVALID)
        resolved = true;
}

bool call_node_has_resolution(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return true;

    bool resolved = false;
    observe_call_token_resolution(hir_token_pos[call_node], resolved);

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return resolved;

    uint path_i = path_id_for_callee_node(callee_node);
    if (valid_path(path_i))
    {
        uint owner_token = path_owner_token[path_i];
        observe_call_token_resolution(owner_token, resolved);
        uint leaf_token = path_leaf_token(path_i);
        if (leaf_token != owner_token)
            observe_call_token_resolution(leaf_token, resolved);
    }

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
        observe_call_token_resolution(hir_member_name_token[callee_node], resolved);

    observe_call_token_resolution(associated_callee_method_token_for_call(call_node), resolved);
    observe_call_token_resolution(value_token_for_node(callee_node), resolved);
    observe_call_token_resolution(hir_token_pos[callee_node], resolved);
    return resolved;
}

uint unresolved_call_error_token(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint path_i = path_id_for_callee_node(callee_node);
    if (valid_path(path_i))
    {
        uint owner_token = path_owner_token[path_i];
        if (valid_token(owner_token) &&
            module_value_path_status[owner_token] != PATH_RESOLVE_STATUS_INVALID &&
            module_value_path_status[owner_token] != PATH_RESOLVE_STATUS_OK)
            return owner_token;

        uint leaf_token = path_leaf_token(path_i);
        if (valid_token(leaf_token))
            return leaf_token;
        if (valid_token(owner_token))
            return owner_token;
    }

    uint token_i = value_token_for_node(callee_node);
    if (valid_token(token_i))
        return token_i;
    token_i = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    return valid_token(token_i) ? token_i : hir_token_pos[call_node];
}

uint unresolved_call_error_detail(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint path_i = path_id_for_callee_node(callee_node);
    if (!valid_path(path_i))
        return 0u;

    uint owner_token = path_owner_token[path_i];
    uint path_status = valid_token(owner_token)
        ? module_value_path_status[owner_token]
        : PATH_RESOLVE_STATUS_INVALID;
    if (path_status == PATH_RESOLVE_STATUS_INVALID ||
        path_status == PATH_RESOLVE_STATUS_OK)
        return 0u;
    return path_status;
}

void validate_unresolved_call_node(uint node)
{
    if (hir_kind[node] != HIR_CALL_EXPR)
        return;
    if (call_node_has_resolution(node))
        return;

    uint token_i = unresolved_call_error_token(node);
    record_error(
        valid_token(token_i) ? token_i : hir_token_pos[node],
        ERR_UNRESOLVED_IDENT,
        unresolved_call_error_detail(node));
}

bool decl_initializer_context_is_array(uint node)
{
    uint type_node = hir_stmt_record[stmt_slot(node, 3u)];
    return valid_node(type_node) &&
           hir_kind[type_node] == HIR_TYPE &&
           hir_type_form[type_node] == HIR_TYPE_FORM_ARRAY;
}

bool token_inside_node_span(uint node, uint token_i)
{
    if (!valid_node(node) || !valid_token(token_i))
        return false;
    uint start = hir_token_pos[node];
    uint end = hir_token_end[node];
    return valid_token(start) && end != INVALID && token_i >= start && token_i < end;
}

bool parser_published_stmt_type_syntax(uint node, uint token_i)
{
    uint stmt = valid_node(node) ? hir_nearest_stmt_node[node] : INVALID;
    if (!valid_node(stmt) || hir_stmt_record[stmt_slot(stmt, 0u)] != STMT_RECORD_KIND_LET)
        return false;
    uint type_node = hir_stmt_record[stmt_slot(stmt, 3u)];
    return token_inside_node_span(type_node, token_i);
}

bool has_type_syntax_ancestor(uint node)
{
    uint cursor = node;
    for (uint step = 0u; step < 8u; step += 1u)
    {
        if (!valid_node(cursor))
            return false;
        if (hir_kind[cursor] == HIR_TYPE)
            return true;
        uint next = parent[cursor];
        if (!valid_node(next) || next == cursor)
            return false;
        cursor = next;
    }
    return false;
}

bool parser_published_type_syntax(uint node, uint token_i)
{
    return has_type_syntax_ancestor(node) ||
           parser_published_stmt_type_syntax(node, token_i) ||
           (valid_token(token_i) &&
            module_type_path_status[token_i] != PATH_RESOLVE_STATUS_INVALID) ||
           (valid_token(token_i) && type_expr_ref_tag[token_i] != TYPE_REF_INVALID);
}

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = hir_scalar_type_for_expr_form(expr_form(node));
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

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
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
        uint callee_node = hir_call_callee_node[node];
        if (!valid_node(callee_node))
            return call_result_type_for_token(token_i);
        if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
        {
            uint member_token = hir_member_name_token[callee_node];
            return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
        }

        uint path_i = path_id_for_callee_node(callee_node);
        if (valid_path(path_i))
        {
            uint owner_token = path_owner_token[path_i];
            uint path_ty = call_result_type_for_token(owner_token);
            if (path_ty != TY_UNKNOWN)
                return path_ty;

            uint leaf_token = path_leaf_token(path_i);
            if (leaf_token != owner_token)
            {
                path_ty = call_result_type_for_token(leaf_token);
                if (path_ty != TY_UNKNOWN)
                    return path_ty;
            }
        }
        uint associated_method = associated_callee_method_token_for_call(node);
        if (valid_token(associated_method))
        {
            uint associated_ty = call_result_type_for_token(associated_method);
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
        uint callee_ty = call_result_type_for_token(callee_token);
        if (callee_ty != TY_UNKNOWN)
            return callee_ty;

        return call_result_type_for_token(token_i);
    }

    return TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
    }

    if (hir_kind[node] == HIR_INDEX_EXPR)
    {
        uint token_i = hir_token_pos[node];
        return valid_token(token_i) ? call_return_type[token_i] : TY_UNKNOWN;
    }

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
        form == HIR_EXPR_DIV)
    {
        uint left_ty = direct_node_type(resolve_expr(expr_left(node)));
        uint right_ty = direct_node_type(resolve_expr(expr_right(node)));
        return left_ty == TY_FLOAT || right_ty == TY_FLOAT ? TY_FLOAT : TY_INT;
    }

    if (form == HIR_EXPR_MOD ||
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
           hir_kind[node] == HIR_STRUCT_LITERAL_EXPR;
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
    uint call_node = call_node_for_expr(root);
    if (valid_node(call_node))
    {
        uint call_ty = direct_node_type(call_node);
        if (call_ty != TY_UNKNOWN)
        {
            value_token = expression_result_token(call_node);
            return call_ty;
        }
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

    uint record_ty = direct_expr_record_type(root);
    if (record_ty != TY_UNKNOWN)
    {
        uint record_node = resolve_expr(root);
        value_token = valid_node(record_node) ? hir_token_pos[record_node] : hir_token_pos[root];
        return record_ty;
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

    uint call_node = call_node_for_expr(expr_node);
    if (valid_node(call_node))
        return direct_node_type(call_node);

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

    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint expected = visible_type_for_token(decl_token);
    if (expected == TY_UNKNOWN)
    {
        uint actual_token = direct_name_expr_token(expr_node);
        if (aggregate_expr_type_ref_mismatch(
                node,
                decl_token,
                expr_node,
                actual_token,
                actual_token,
                0u))
            record_error(actual_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    if (resolved_call_expr_has_unknown_result(expr_node))
        return;

    // Array declarations are represented by an instance ref, while
    // `visible_type` intentionally exposes their scalar element type to value
    // expression inference. Do not compare the literal against that flattened
    // scalar here: the parallel array-literal instance pass validates its
    // bounded length and every linked element against the full array ref.
    if (decl_initializer_context_is_array(node) &&
        valid_node(direct_array_literal_node(expr_node)))
        return;

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

    if (actual == expected &&
        aggregate_type_code_for_ref_check(expected) &&
        aggregate_expr_type_ref_mismatch(
            node,
            decl_token,
            expr_node,
            value_token,
            valid_token(value_token) ? value_token : decl_token,
            expected * 256u + actual))
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
    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint target_token = INVALID;
    uint expected = first_value_type_from_node(target_node, target_token);
    if (expected == TY_UNKNOWN)
    {
        target_token = direct_name_expr_token(target_node);
        uint actual_token = direct_name_expr_token(expr_node);
        if (aggregate_expr_type_ref_mismatch(
                node,
                target_token,
                expr_node,
                actual_token,
                actual_token,
                0u))
            record_error(actual_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    if (resolved_call_expr_has_unknown_result(expr_node))
        return;

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

    if (actual == expected &&
        aggregate_type_code_for_ref_check(expected) &&
        aggregate_expr_type_ref_mismatch(
            node,
            target_token,
            expr_node,
            value_token,
            valid_token(value_token) ? value_token : target_token,
            expected * 256u + actual))
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
    uint fn_token = enclosing_function_token_for_token(token_i);
    return valid_token(fn_token) ? call_return_type[fn_token] : TY_UNKNOWN;
}

uint enclosing_function_token_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;

    uint encoded_fn = enclosing_fn[token_i];
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint enclosing_function_return_type_token_for_token(uint token_i)
{
    uint fn_token = enclosing_function_token_for_token(token_i);
    return valid_token(fn_token) ? call_return_type_token[fn_token] : INVALID;
}

bool enclosing_function_instance_return_mismatch(
    uint node,
    uint return_token,
    uint actual_token,
    uint error_token,
    uint detail)
{
    uint fn_token = enclosing_function_token_for_token(return_token);
    if (!valid_token(fn_token) || fn_return_ref_tag[fn_token] != TYPE_REF_INSTANCE)
        return false;

    uint actual_tag = TYPE_REF_INVALID;
    uint actual_payload = INVALID;
    if (!read_decl_type_ref(actual_token, actual_tag, actual_payload))
        return false;
    if (actual_tag != TYPE_REF_INSTANCE)
        return true;

    return aggregate_instance_ref_mismatch(
        node,
        fn_return_ref_payload[fn_token],
        actual_payload,
        call_return_type_token[fn_token],
        actual_token,
        error_token,
        detail);
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

    uint direct_actual_token = direct_name_expr_token(expr_node);
    uint direct_error_token = valid_token(direct_actual_token) ? direct_actual_token : return_token;
    if (enclosing_function_instance_return_mismatch(
            node,
            return_token,
            direct_actual_token,
            direct_error_token,
            0u))
    {
        record_error(direct_error_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    if (expected == TY_UNKNOWN)
        return;

    if (resolved_call_expr_has_unknown_result(expr_node))
        return;

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
    {
        actual = first_struct_literal_type_from_node(expr_node, value_token);
    }
    if (actual == TY_UNKNOWN)
        actual = first_value_type_from_node(expr_node, value_token);
    if (actual == TY_UNKNOWN)
        return;

    uint error_token = valid_token(value_token) ? value_token : return_token;
    if (direct_unsupported_symbolic_array_call(expr_node, actual))
        record_error(error_token, ERR_ASSIGN_MISMATCH, actual);

    if (actual == expected &&
        aggregate_type_code_for_ref_check(expected) &&
        aggregate_expr_type_ref_mismatch(
            node,
            enclosing_function_return_type_token_for_token(return_token),
            expr_node,
            value_token,
            error_token,
            expected * 256u + actual))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
        return;
    }

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
    if (parser_published_type_syntax(node, token_i))
        return;
    if (module_value_path_associated_method_token[token_i] != INVALID)
        return;
    if (method_call_name_id[token_i] != INVALID)
        return;
    if (module_value_path_call_leaf[token_i] != 0u)
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
        if (status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE &&
            token_i == hir_token_pos[node])
        {
            uint fallback_token = first_bound_arg_token_after_bound(node);
            if (valid_token(fallback_token))
                token_i = fallback_token;
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

bool predicate_status_accepts_method_validation(uint status_value)
{
    return status_value == INVALID ||
           status_value == PREDICATE_STATUS_OK ||
           status_value == PREDICATE_STATUS_MISSING_METHOD ||
           status_value == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
           status_value == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
           status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
           status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
           status_value == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
           status_value == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
           status_value == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
           status_value == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
           status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW;
}

void validate_unsupported_trait_node(uint node)
{
    uint prod = node_kind[node];
    if (prod == PROD_IMPL_TRAIT || prod == PROD_IMPL_INHERENT)
    {
        uint status_value = predicate_status[node];
        uint method_detail_token = INVALID;
        uint owner_hir = raw_to_compact_hir[node];
        if (owner_hir != INVALID && owner_hir < min(compact_hir_count[0u], gParams.n_hir_nodes))
        {
            uint error_row = predicate_method_validation_first_error_row[owner_hir];
            if (error_row != INVALID && error_row < active_hir_node_count())
            {
                uint method_status = predicate_method_validation_status[error_row];
                if (method_status != INVALID &&
                    method_status != PREDICATE_STATUS_OK &&
                    predicate_status_accepts_method_validation(status_value))
                {
                    status_value = method_status;
                    method_detail_token = predicate_method_validation_detail_token[error_row];
                }
            }
        }
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
            else if (valid_token(method_detail_token))
            {
                token_i = method_detail_token;
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
    uint dense = valid_node(node) ? raw_to_compact_hir[node] : INVALID;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint row = dense < hir_count
        ? compact_method_row_for_hir(compact_method_cores, method_count, dense)
        : INVALID;
    uint flags = row < method_count
        ? compact_method_signatures[row].metadata >> 16u
        : 0u;
    if ((flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC;
    if ((flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
    return PREDICATE_STATUS_OK;
}

uint method_contract_name_token_from_rows(uint node)
{
    uint dense = valid_node(node) ? raw_to_compact_hir[node] : INVALID;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint row = dense < hir_count
        ? compact_method_row_for_hir(compact_method_cores, method_count, dense)
        : INVALID;
    uint token_i = row < method_count ? compact_method_cores[row].name_token : INVALID;
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
    uint status_value = parser_method_signature_status(node);
    if (status_value != PREDICATE_STATUS_OK)
        return status_value;

    status_value = predicate_status[node];
    if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
        return status_value;

    status_value = predicate_method_contract_status[node];
    if (status_value != INVALID && status_value != PREDICATE_STATUS_OK)
        return status_value;

    return PREDICATE_STATUS_OK;
}

void validate_unsupported_method_contract_node(uint node)
{
    if (!method_contract_production(node))
        return;

    uint status_value = method_contract_status_from_rows(node);
    if (status_value == PREDICATE_STATUS_OK)
        return;

    bool parser_signature_error =
        status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
    uint token_i = parser_signature_error
        ? hir_token_pos[node]
        : predicate_bound_first_arg_token[node];
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
    clear_aggregate_compare_request(node);
    validate_call_argument_width_node(node);
    validate_unresolved_call_node(node);
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
