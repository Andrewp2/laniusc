// HIR condition validation.
//
// This pass consumes parser-owned statement records and attributed expression
// records. It intentionally handles simple single-value conditions here and
// leaves compound expressions to dedicated expression-attribution passes rather
// than scanning condition token ranges.

import generated_parse_production_ids;
import hir_records;
import status;
import tree_walk;

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
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_arg_node;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_status;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint INTRINSIC_NONE = 0u;

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

static const uint TYPE_REF_GENERIC_PARAM = 2u;

static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
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

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
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

uint condition_parent_record(uint node)
{
    return parent[node];
}

uint condition_first_child_record(uint node)
{
    return first_child[node];
}

uint condition_next_sibling_record(uint node)
{
    return next_sibling[node];
}

uint condition_first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = condition_first_child_record(node);
    return valid_node(child) && condition_parent_record(child) == node ? child : INVALID;
}

uint condition_next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = condition_next_sibling_record(node);
    return valid_node(sibling) &&
                   condition_parent_record(sibling) == condition_parent_record(node)
        ? sibling
        : INVALID;
}

public struct ConditionLinkedGraph : ITreeLinkedGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return condition_parent_record(node);
    }

    public static uint first_child(uint node)
    {
        return condition_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return condition_next_sibling_record(node);
    }
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

bool match_pattern_ancestor(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        uint prod = node_kind[node];
        if (prod == PROD_PATTERN_IDENT ||
            prod == PROD_PATTERN_PLAIN ||
            prod == PROD_PATTERN_TUPLE)
            return true;
        if (prod == PROD_MATCH_ARM)
            return false;
        node = parent[node];
    }
    return false;
}

bool type_syntax_ancestor(uint node)
{
    uint cur = condition_parent_record(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (hir_kind[cur] == HIR_TYPE)
            return true;

        uint kind = node_kind[cur];
        if (kind == PROD_TYPE_IDENT ||
            kind == PROD_TYPE_PATH ||
            kind == PROD_TYPE_PATH_IDENT ||
            kind == PROD_TYPE_PATH_MORE ||
            kind == PROD_TYPE_ARGS_SOME ||
            kind == PROD_TYPE_ARGS_MORE ||
            kind == PROD_TYPE_ARGS_AFTER_COMMA_MORE)
            return true;

        if (hir_kind[cur] == HIR_EXPR ||
            hir_kind[cur] == HIR_STMT ||
            hir_kind[cur] == HIR_BLOCK ||
            hir_kind[cur] == HIR_FN ||
            hir_kind[cur] == HIR_FILE)
            return false;

        cur = condition_parent_record(cur);
    }
    return false;
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
        uint visible = visible_type_for_token(token_i);
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
        uint callee_node = hir_call_callee_node[node];
        if (!valid_node(callee_node))
            return TY_UNKNOWN;
        if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
        {
            uint member_token = hir_member_name_token[callee_node];
            return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
        }
        uint callee_token = hir_token_pos[callee_node];
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

uint next_descendant_node(uint root, uint cur)
{
    uint next;
    return tree_next_preorder_within<ConditionLinkedGraph>(
        root,
        cur,
        96u,
        next) ? next : INVALID;
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

uint preferred_result_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    uint result_ty = TY_UNKNOWN;
    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (expression_result_node(node))
        {
            uint token_i = INVALID;
            uint ty = direct_node_type(node);
            if (ty != TY_UNKNOWN)
            {
                if (!valid_token(value_token))
                {
                    token_i = hir_token_pos[node];
                    value_token = valid_token(token_i) ? token_i : INVALID;
                }
                return ty;
            }
        }
        node = next_descendant_node(root, node);
    }
    return result_ty;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(root);
    if (record_ty != TY_UNKNOWN)
    {
        uint record_node = resolve_expr(root);
        value_token = valid_node(record_node) ? hir_token_pos[record_node] : hir_token_pos[root];
        return record_ty;
    }

    uint resolved = resolve_expr(root);
    if (expression_result_node(resolved))
    {
        uint root_ty = direct_node_type(resolved);
        if (root_ty != TY_UNKNOWN)
        {
            value_token = hir_token_pos[resolved];
            return root_ty;
        }
    }

    uint result_ty = preferred_result_type_from_node(root, value_token);
    if (result_ty != TY_UNKNOWN)
        return result_ty;

    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        uint sibling = next_sibling[node];
        if (hir_kind[node] == HIR_NAME_EXPR && sibling != INVALID &&
            sibling < active_hir_node_count() &&
            (hir_kind[sibling] == HIR_INDEX_EXPR || hir_kind[sibling] == HIR_MEMBER_EXPR ||
             hir_kind[sibling] == HIR_STRUCT_LITERAL_EXPR))
        {
            node = next_descendant_node(root, node);
            continue;
        }

        uint token_i = hir_token_pos[node];
        uint ty = direct_node_type(node);
        if (ty != TY_UNKNOWN)
        {
            value_token = valid_token(token_i) ? token_i : INVALID;
            return ty;
        }

        if (hir_kind[node] == HIR_CALL_EXPR)
            return TY_UNKNOWN;

        node = next_descendant_node(root, node);
    }
    return TY_UNKNOWN;
}

uint first_struct_literal_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR || node_kind[node] == PROD_STRUCT_LIT)
        {
            uint ty = direct_node_type(node);
            if (ty != TY_UNKNOWN)
            {
                value_token = hir_token_pos[node];
                return ty;
            }
        }
        node = next_descendant_node(root, node);
    }
    return TY_UNKNOWN;
}

bool direct_contextual_aggregate_literal_node(uint context_node, uint root)
{
    if (!valid_node(context_node))
        return false;

    uint node = resolve_expr(root);
    if (!valid_node(node))
        return false;

    if (hir_kind[node] == HIR_ARRAY_EXPR &&
        hir_array_lit_context_stmt_node[node] == context_node)
        return true;

    if ((hir_kind[node] == HIR_STRUCT_LITERAL_EXPR || node_kind[node] == PROD_STRUCT_LIT) &&
        hir_struct_lit_context_stmt_node[node] == context_node)
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

    uint found = TY_UNKNOWN;
    uint count = 0u;
    uint node = expr_node;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (hir_kind[node] == HIR_CALL_EXPR || hir_kind[node] == HIR_MEMBER_EXPR)
            return TY_UNKNOWN;

        uint ty = direct_node_type(node);
        if (ty == TY_UNKNOWN)
        {
            node = next_descendant_node(expr_node, node);
            continue;
        }
        if (found != TY_UNKNOWN && found != ty)
            return TY_UNKNOWN;
        found = ty;
        count += 1u;
        node = next_descendant_node(expr_node, node);
    }
    return count == 1u ? found : TY_UNKNOWN;
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
        return;

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
        return;

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

void validate_return_node(uint node)
{
    if (hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[node];
    uint expected = enclosing_function_return_type_for_token(return_token);

    uint expr_node = hir_stmt_record[stmt_slot(node, 1u)];
    uint value_token = INVALID;
    uint actual = TY_UNKNOWN;
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

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return;
    // Intrinsic call heads are resolved by the call-record pass; call arguments
    // remain ordinary value expressions and are validated by their own HIR rows.
    if (is_intrinsic_name(token_i))
        return;
    if (match_pattern_ancestor(node))
        return;
    if (type_syntax_ancestor(node))
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
    bool resolved_by_decl = valid_token(visible_decl[token_i]);
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

void validate_generic_type_ref_node(uint node)
{
    if (hir_kind[node] != HIR_TYPE)
        return;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return;

    if (type_expr_ref_tag[token_i] == TYPE_REF_GENERIC_PARAM)
    {
        uint payload = type_expr_ref_payload[token_i];
        if (!valid_token(payload) ||
            type_generic_param_slot_by_token[payload] == INVALID)
            record_error(token_i, ERR_UNRESOLVED_IDENT, 0u);
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

    uint cur = condition_parent_record(node);
    bool top_level_predicate = false;
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        uint cur_kind = node_kind[cur];
        if (cur_kind == PROD_BOUND_TYPE_ARGS_SOME)
            break;
        if (cur_kind == PROD_BOUND_TYPE_IDENT || cur_kind == PROD_BOUND_TYPE_REF)
            break;
        if (cur_kind == PROD_TYPE_PARAM_BOUND_LIST)
        {
            top_level_predicate = true;
            break;
        }
        if (cur_kind == PROD_TYPE_PARAM_BOUND || cur_kind == PROD_WHERE_TYPE_BOUND)
            break;
        cur = condition_parent_record(cur);
    }

    if (!top_level_predicate)
        return;

    uint status_value = predicate_status[node];
    if (status_value != PREDICATE_STATUS_OK)
    {
        uint token_i = hir_token_pos[node];
        bool unsupported_predicate_row =
            status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
            status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND ||
            status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        uint code = status_value == PREDICATE_STATUS_INVALID_SUBJECT
            ? ERR_UNRESOLVED_IDENT
            : (unsupported_predicate_row ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_UNKNOWN_TYPE);
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
            bool unsupported_predicate_row =
                status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
            bool invalid_method =
                status_value == PREDICATE_STATUS_INVALID_ARG ||
                status_value == PREDICATE_STATUS_MISSING_METHOD ||
                status_value == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
                status_value == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
                status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE ||
                status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
                status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
                status_value == PREDICATE_STATUS_OVERLAPPING_IMPL ||
                status_value == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD;
            uint code = status_value == PREDICATE_STATUS_INVALID_SUBJECT
                ? ERR_UNRESOLVED_IDENT
                : (unsupported_predicate_row
                    ? ERR_TRAIT_BOUND_UNSATISFIED
                    : (invalid_method ? ERR_BAD_HIR : ERR_UNKNOWN_TYPE));
            if ((status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
                 status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE) &&
                valid_token(predicate_bound_first_arg_token[node]))
            {
                token_i = predicate_bound_first_arg_token[node];
            }
            record_error(valid_token(token_i) ? token_i : 0u, code, status_value);
        }
    }
}

uint trait_method_contract_status(uint node)
{
    uint child = condition_first_child_node(node);
    [loop]
    for (uint guard = 0u; guard < 8u && valid_node(child); guard += 1u)
    {
        uint kind = node_kind[child];
        if (kind == PROD_ENUM_TYPE_PARAMS_SOME)
            return PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC;
        if (kind == PROD_WHERE_SOME)
            return PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
        child = condition_next_sibling_node(child);
    }
    return PREDICATE_STATUS_OK;
}

void validate_unsupported_trait_method_node(uint node)
{
    uint prod = node_kind[node];
    if (prod != PROD_TRAIT_METHOD && prod != PROD_TRAIT_METHOD_PUB)
        return;

    uint status_value = predicate_status[node];
    if (status_value == INVALID || status_value == PREDICATE_STATUS_OK)
        status_value = trait_method_contract_status(node);
    if (status_value == PREDICATE_STATUS_OK)
        return;

    uint token_i = predicate_bound_first_arg_token[node];
    if (!valid_token(token_i))
        token_i = hir_token_pos[node];
    record_error(valid_token(token_i) ? token_i : 0u, ERR_BAD_HIR, status_value);
}

void validate_call_argument_width_node(uint node)
{
    if (hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint arg_count = hir_call_arg_count[node];
    if (arg_count <= PARAM_CACHE_STRIDE)
        return;

    uint callee_node = hir_call_callee_node[node];
    uint token_i = valid_node(callee_node) ? hir_token_pos[callee_node] : hir_token_pos[node];
    record_error(
        valid_token(token_i) ? token_i : 0u,
        ERR_CALL_MISMATCH,
        PARAM_CACHE_STRIDE * 256u + arg_count);
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
    validate_unsupported_trait_method_node(node);
}
