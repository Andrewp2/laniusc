// Widen parser-owned call expression spans after callee links are known.
//
// Postfix call grammar rows naturally start at the argument list. HIR call
// records represent the whole call expression, including the callee.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> out_emit_pos;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> canonical_raw_to_dense;
StructuredBuffer<uint> hir_call_callee_node;

RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_CALL_EXPR = 19u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirCall.uses_status_count != 0u ? min(gHirCall.n, tree_count_status[5u]) : gHirCall.n;
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

bool is_postfix_operator(uint production)
{
    return production == PROD_POSTFIX_CALL || production == PROD_POSTFIX_INDEX ||
           production == PROD_POSTFIX_MEMBER ||
           production == PROD_POSTFIX_TRY;
}

uint callee_span_start(uint callee)
{
    // A preceding call can be widened by another lane in this dispatch.
    // Follow immutable grammar ownership to the original callee instead.
    for (uint depth = 0u; depth < active_node_count() && valid_node(callee); depth++)
    {
        if (!is_postfix_operator(node_kind[callee])) return out_emit_pos[callee];
        uint owner = parent[callee];
        if (!valid_node(owner)) return INVALID;
        if (is_postfix_operator(node_kind[owner])) callee = owner;
        else if (node_kind[owner] == PROD_POSTFIX) callee = first_child[owner];
        else return out_emit_pos[callee];
    }
    return INVALID;
}

uint call_span_end(uint call)
{
    uint args = first_child[call];
    uint tail = valid_node(args) ? next_sibling[args] : INVALID;
    if (!valid_node(tail) || parent[tail] != call) return INVALID;

    // The continuation begins after this call's closing parenthesis, at its
    // own punctuation or the following token for an empty continuation. This
    // position has not been changed by expression-span publication.
    uint end = out_emit_pos[tail];
    return is_postfix_operator(node_kind[tail]) || node_kind[tail] == PROD_POSTFIX_END
        ? end : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint record_row = gHirCall.retain_debug_rows != 0u
        ? node
        : canonical_raw_to_dense[node];
    if (record_row == INVALID)
        return;
    uint callee = hir_call_callee_node[record_row];
    if (!valid_node(callee))
        return;

    uint callee_start = callee_span_start(callee);
    uint call_start = hir_token_pos[node];
    if (callee_start != INVALID &&
        (call_start == INVALID || callee_start < call_start))
        hir_token_pos[node] = callee_start;

    uint end = call_span_end(node);
    if (end != INVALID)
        hir_token_end[node] = end;
}
