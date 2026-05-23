// Validates first-order trait obligations at direct generic call sites.
//
// This pass consumes predicate rows plus HIR call/parameter/type attribution
// records. It intentionally stays bounded: direct calls only, concrete impl
// rows only, and trait bounds with at most two type arguments.

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
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_token;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_BAD_HIR = 6u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

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

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_UNSATISFIED_BOUND = 9u;
static const uint PREDICATE_STATUS_AMBIGUOUS_BOUND = 10u;

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

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint obligation_parent_record(uint node)
{
    return parent[node];
}

uint obligation_first_child_record(uint node)
{
    return first_child[node];
}

uint obligation_next_sibling_record(uint node)
{
    return next_sibling[node];
}

public struct PredicateObligationLinkedGraph : ITreeLinkedGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return obligation_parent_record(node);
    }

    public static uint first_child(uint node)
    {
        return obligation_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return obligation_next_sibling_record(node);
    }
}

uint next_descendant_node(uint root, uint cur)
{
    uint next;
    return tree_next_preorder_within<PredicateObligationLinkedGraph>(
        root,
        cur,
        96u,
        next)
        ? next
        : INVALID;
}

uint expr_record_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_left(node);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
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
        return visible_type_for_token(token_i);

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
    }

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR || node_kind[node] == PROD_STRUCT_LIT)
    {
        uint head_node = hir_struct_lit_head_node[node];
        if (!valid_node(head_node))
            return TY_UNKNOWN;
        return visible_type_for_token(hir_token_pos[head_node]);
    }

    if (hir_kind[node] == HIR_INDEX_EXPR || hir_kind[node] == HIR_MATCH_EXPR)
        return call_return_type[token_i];

    if (hir_kind[node] == HIR_CALL_EXPR && token_i > 0u)
        return call_return_type[token_i - 1u];

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
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        return visible_type_for_token(token_i);
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

uint preferred_result_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (expression_result_node(node))
        {
            uint ty = direct_node_type(node);
            if (ty != TY_UNKNOWN)
            {
                uint token_i = hir_token_pos[node];
                value_token = valid_token(token_i) ? token_i : INVALID;
                return ty;
            }
        }
        node = next_descendant_node(root, node);
    }
    return TY_UNKNOWN;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(root);
    if (record_ty != TY_UNKNOWN)
    {
        value_token = hir_token_pos[root];
        return record_ty;
    }

    if (expression_result_node(root))
    {
        uint root_ty = direct_node_type(root);
        if (root_ty != TY_UNKNOWN)
        {
            value_token = hir_token_pos[root];
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

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = type_code_for_ref(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    if (ty != TY_UNKNOWN)
        return ty;
    return visible_type_for_token(token);
}

bool same_name(uint lhs, uint rhs)
{
    if (!valid_token(lhs) || !valid_token(rhs))
        return false;
    uint lhs_name = name_id_by_token[lhs];
    uint rhs_name = name_id_by_token[rhs];
    return lhs_name != INVALID && lhs_name == rhs_name;
}

bool generic_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_TYPE_PARAM;
}

uint generic_param_slot_for_name(uint decl_node, uint name_token)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint end = min(subtree_end[decl_node], active_hir_node_count());
    uint slot = 0u;
    [loop]
    for (uint node = decl_node + 1u; node < end; node += 1u)
    {
        if (!generic_param_node(node))
            continue;

        uint param_token = hir_token_pos[node];
        if (valid_token(param_token) && name_id_by_token[param_token] == name_id)
            return slot;
        slot += 1u;
    }

    return INVALID;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
}

uint call_arg_node_for_ordinal(uint call_node, uint ordinal)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        uint packed = hir_call_arg_parent_call[node];
        if (hir_node_ordinal_node(packed) == call_node &&
            hir_node_ordinal_ordinal(packed) == ordinal)
            return node;
    }
    return INVALID;
}

uint child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint param_type_node(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;

    uint prod = node_kind[param_node];
    uint child = child_node(param_node);
    if (!valid_node(child))
        return INVALID;

    if (prod == PROD_PARAM_NAMED)
        return hir_type_form[child] != HIR_TYPE_FORM_NONE ? child : INVALID;

    if (prod == PROD_PARAM_SELF)
    {
        uint typed_child = child_node(child);
        return valid_node(typed_child) && hir_type_form[typed_child] != HIR_TYPE_FORM_NONE
                   ? typed_child
                   : INVALID;
    }

    return INVALID;
}

bool param_record_uses_generic_slot(uint param_node, uint slot)
{
    if (!valid_node(param_node))
        return false;

    uint type_node = param_type_node(param_node);
    if (!valid_node(type_node))
        return false;

    uint token = hir_token_pos[type_node];
    if (!valid_token(token))
        return false;

    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag != TYPE_REF_GENERIC_PARAM || !valid_token(payload))
        return false;

    return type_generic_param_slot_by_token[payload] == slot;
}

uint actual_type_for_generic_slot(uint call_node, uint fn_node, uint slot)
{
    if (!valid_node(call_node) || !valid_node(fn_node) || slot == INVALID)
        return TY_UNKNOWN;

    uint found = TY_UNKNOWN;
    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        uint4 record = hir_param_record[node];
        if (record[HIR_PARAM_RECORD_FN] != fn_node)
            continue;
        if (!param_record_uses_generic_slot(node, slot))
            continue;

        uint arg_node = call_arg_node_for_ordinal(call_node, record[HIR_PARAM_RECORD_ORDINAL]);
        uint value_token = INVALID;
        uint actual = first_value_type_from_node(arg_node, value_token);
        if (actual == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (found == TY_UNKNOWN)
            found = actual;
        else if (found != actual)
            return TY_UNKNOWN;
    }
    return found;
}

uint predicate_bound_arg_token(uint pred_node, uint ordinal)
{
    if (ordinal == 0u)
        return predicate_bound_first_arg_token[pred_node];
    if (ordinal == 1u)
        return predicate_bound_second_arg_token[pred_node];
    return INVALID;
}

uint predicate_arg_concrete_type(uint pred_node, uint fn_node, uint call_node, uint ordinal)
{
    uint token = predicate_bound_arg_token(pred_node, ordinal);
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint slot = generic_param_slot_for_name(fn_node, token);
    if (slot != INVALID)
        return actual_type_for_generic_slot(call_node, fn_node, slot);

    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint payload_slot = type_generic_param_slot_by_token[payload];
        return actual_type_for_generic_slot(call_node, fn_node, payload_slot);
    }
    return type_code_for_ref(tag, payload);
}

bool impl_row_satisfies_bound(
    uint impl_node,
    uint bound_token,
    uint subject_ty,
    uint required_arg0_ty,
    uint required_arg1_ty,
    uint arg_count)
{
    if (!valid_node(impl_node) || predicate_owner_node[impl_node] != impl_node)
        return false;
    if (predicate_status[impl_node] != PREDICATE_STATUS_OK)
        return false;
    if (!same_name(predicate_bound_token[impl_node], bound_token))
        return false;
    if (type_code_for_type_token(predicate_subject_token[impl_node]) != subject_ty)
        return false;
    if (predicate_bound_arg_count[impl_node] != arg_count)
        return false;
    if (arg_count >= 1u)
    {
        uint impl_arg0_ty = type_code_for_type_token(predicate_bound_first_arg_token[impl_node]);
        if (impl_arg0_ty == TY_UNKNOWN || impl_arg0_ty != required_arg0_ty)
            return false;
    }
    if (arg_count >= 2u)
    {
        uint impl_arg1_ty = type_code_for_type_token(predicate_bound_second_arg_token[impl_node]);
        if (impl_arg1_ty == TY_UNKNOWN || impl_arg1_ty != required_arg1_ty)
            return false;
    }
    return true;
}

uint concrete_impl_match_count_for_bound(
    uint bound_token,
    uint subject_ty,
    uint required_arg0_ty,
    uint required_arg1_ty,
    uint arg_count)
{
    uint matches = 0u;
    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        if (impl_row_satisfies_bound(
                node,
                bound_token,
                subject_ty,
                required_arg0_ty,
                required_arg1_ty,
                arg_count))
        {
            matches += 1u;
            if (matches > 1u)
                return matches;
        }
    }
    return matches;
}

void validate_trait_obligation_for_call(uint pred, uint fn_node, uint node)
{
    if (hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(node);
    if (!valid_token(callee_token))
        return;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    if (!valid_node(fn_node) || hir_token_pos[fn_node] != fn_token)
        return;

    uint subject_token = predicate_subject_token[pred];
    uint subject_slot = generic_param_slot_for_name(fn_node, subject_token);
    uint subject_ty = actual_type_for_generic_slot(node, fn_node, subject_slot);
    if (subject_ty == TY_UNKNOWN)
    {
        record_error(callee_token, ERR_BAD_HIR, PREDICATE_STATUS_UNSATISFIED_BOUND);
        return;
    }

    uint arg_count = predicate_bound_arg_count[pred];
    if (arg_count > 2u)
    {
        record_error(callee_token, ERR_BAD_HIR, PREDICATE_STATUS_UNSATISFIED_BOUND);
        return;
    }

    uint required_arg0_ty = TY_UNKNOWN;
    uint required_arg1_ty = TY_UNKNOWN;
    if (arg_count >= 1u)
    {
        required_arg0_ty = predicate_arg_concrete_type(pred, fn_node, node, 0u);
        if (required_arg0_ty == TY_UNKNOWN)
        {
            record_error(callee_token, ERR_BAD_HIR, PREDICATE_STATUS_UNSATISFIED_BOUND);
            return;
        }
    }
    if (arg_count >= 2u)
    {
        required_arg1_ty = predicate_arg_concrete_type(pred, fn_node, node, 1u);
        if (required_arg1_ty == TY_UNKNOWN)
        {
            record_error(callee_token, ERR_BAD_HIR, PREDICATE_STATUS_UNSATISFIED_BOUND);
            return;
        }
    }

    uint impl_count = concrete_impl_match_count_for_bound(
        predicate_bound_token[pred],
        subject_ty,
        required_arg0_ty,
        required_arg1_ty,
        arg_count);
    if (impl_count != 1u)
    {
        record_error(
            callee_token,
            ERR_BAD_HIR,
            impl_count == 0u ? PREDICATE_STATUS_UNSATISFIED_BOUND
                             : PREDICATE_STATUS_AMBIGUOUS_BOUND);
        return;
    }
}

void validate_predicate_obligations(uint pred)
{
    if (predicate_status[pred] != PREDICATE_STATUS_OK)
        return;

    uint fn_node = predicate_owner_node[pred];
    if (!valid_node(fn_node))
        return;

    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        validate_trait_obligation_for_call(pred, fn_node, node);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    validate_predicate_obligations(node);
}
