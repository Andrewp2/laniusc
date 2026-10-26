// Materialize independent member fields and index spans in one semantic-row walk.

import generated_parse_production_ids;
import parser.hir.postfix_sequence;

struct Params
{
    uint n;
    uint uses_status_count;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gHirPostfix;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> out_emit_pos;
StructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> hir_member_receiver_node;
RWStructuredBuffer<uint> hir_member_receiver_token;
RWStructuredBuffer<uint> hir_member_name_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_EXPR_TRY = 37u;
static const uint HIR_TRY_EXPR = 36u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint PARSER_FEATURE_MEMBERS = 0x00000040u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirPostfix.uses_status_count != 0u
        ? min(gHirPostfix.n, tree_count_status[5u])
        : gHirPostfix.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = parent[node];
    return valid_node(value) ? value : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = first_child[node];
    return valid_node(value) ? value : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = prev_sibling[node];
    return valid_node(value) ? value : INVALID;
}

bool is_postfix_operator(uint prod)
{
    return prod == PROD_POSTFIX_CALL || prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER ||
           prod == PROD_POSTFIX_TRY;
}

uint token_before(uint token)
{
    return token != INVALID && token > 0u ? token - 1u : INVALID;
}

uint member_name_token_for_node(uint member_node)
{
    if (!valid_node(member_node))
        return INVALID;

    // The optional argument list begins immediately after the member name.
    uint arguments = first_child_node(member_node);
    uint argument_token = valid_node(arguments) ? out_emit_pos[arguments] : INVALID;
    return argument_token != INVALID && argument_token > out_emit_pos[member_node]
        ? argument_token - 1u : INVALID;
}

uint postfix_operator_head_token(uint operator_node)
{
    if (!valid_node(operator_node))
        return INVALID;
    if (node_kind[operator_node] == PROD_POSTFIX_MEMBER)
        return member_name_token_for_node(operator_node);
    return token_before(out_emit_pos[operator_node]);
}

uint receiver_token_for_node(uint receiver_node)
{
    if (!valid_node(receiver_node))
        return INVALID;
    if (node_kind[receiver_node] == PROD_POSTFIX_INDEX)
    {
        uint base = receiver_node;
        for (uint guard = 0u; guard < active_node_count(); guard += 1u)
        {
            if (!valid_node(base) ||
                expr_record(base, HIR_EXPR_RECORD_FORM) != HIR_EXPR_INDEX)
                break;
            uint next = expr_record(base, HIR_EXPR_RECORD_LEFT);
            if (!valid_node(next) || next == base)
                break;
            base = next;
        }
        return valid_node(base) ? out_emit_pos[base] : INVALID;
    }
    // `value?` publishes its result type at its own `?` token.
    if (node_kind[receiver_node] == PROD_POSTFIX_TRY)
        return out_emit_pos[receiver_node];
    if (is_postfix_operator(node_kind[receiver_node]))
        return postfix_operator_head_token(receiver_node);
    return out_emit_pos[receiver_node];
}

uint receiver_node_for_member(uint member_node)
{
    uint previous = previous_sibling_node(member_node);
    if (valid_node(previous) && is_postfix_operator(node_kind[previous]))
        return previous;

    uint owner = parent_node(member_node);
    if (!valid_node(owner))
        return INVALID;
    if (is_postfix_operator(node_kind[owner]))
        return owner;
    return hir_is_postfix_sequence_owner(node_kind[owner]) ? first_child_node(owner) : INVALID;
}

uint expr_record(uint node, uint field)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + field];
}

void publish_member(uint node)
{
    uint receiver = receiver_node_for_member(node);
    uint receiver_token = receiver_token_for_node(receiver);
    uint member_token = member_name_token_for_node(node);
    if (receiver_token == INVALID || member_token == INVALID)
        return;

    hir_member_receiver_node[node] = receiver;
    hir_member_receiver_token[node] = receiver_token;
    hir_member_name_token[node] = member_token;
}

uint postfix_base_start(uint base)
{
    // Continuations are nested grammar children. Walk their immutable owner
    // links to the original value instead of reading an earlier index's span
    // while another lane is widening it. Call and member spans widen later.
    for (uint depth = 0u; depth < active_node_count() && valid_node(base); depth++)
    {
        if (!is_postfix_operator(node_kind[base])) return out_emit_pos[base];
        uint owner = parent_node(base);
        if (!valid_node(owner)) return INVALID;
        if (is_postfix_operator(node_kind[owner])) base = owner;
        else if (hir_is_postfix_sequence_owner(node_kind[owner])) base = first_child_node(owner);
        else return out_emit_pos[base];
    }
    return INVALID;
}

void publish_index_span(uint node)
{
    uint form = expr_record(node, HIR_EXPR_RECORD_FORM);
    if (form != HIR_EXPR_INDEX && form != HIR_EXPR_TRY)
        return;

    uint base = expr_record(node, HIR_EXPR_RECORD_LEFT);
    if (!valid_node(base))
        return;

    uint base_start = postfix_base_start(base);
    uint index_start = hir_token_pos[node];
    if (base_start != INVALID &&
        (index_start == INVALID || base_start < index_start))
        hir_token_pos[node] = base_start;

    // The index grammar owns its closing bracket and continuation. The
    // operand's semantic span may include empty-tail anchors, and another
    // lane can be publishing a nested index span in this dispatch. Its end
    // plus one is therefore neither a boundary nor a stable input.
    // `value?` has no bracket operand: its only child is the continuation.
    uint operand = form == HIR_EXPR_TRY ? INVALID : first_child_node(node);
    uint tail = form == HIR_EXPR_TRY ? first_child_node(node)
        : valid_node(operand) ? next_sibling[operand] : INVALID;
    if (valid_node(tail) && parent[tail] == node &&
        (is_postfix_operator(node_kind[tail]) || node_kind[tail] == PROD_POSTFIX_END))
        hir_token_end[node] = out_emit_pos[tail];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID)
        return;

    uint kind = hir_kind[node];
    if ((gHirPostfix.parser_feature_flags & PARSER_FEATURE_MEMBERS) != 0u &&
        kind == HIR_MEMBER_EXPR)
    {
        hir_member_receiver_node[node] = INVALID;
        hir_member_receiver_token[node] = INVALID;
        hir_member_name_token[node] = INVALID;
        publish_member(node);
    }
    else if (kind == HIR_INDEX_EXPR || kind == HIR_TRY_EXPR)
        publish_index_span(node);
}
