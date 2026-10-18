// Widen parser-owned member expression spans after member metadata is published.
//
// The grammar node for a member tail naturally starts at the dot/member token.
// HIR consumers need the expression span instead: receiver through member name.
// This pass uses the already-published receiver relation, avoiding a race with
// chained member metadata derivation.

import generated_parse_production_ids;
import parser.hir.postfix_sequence;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMember;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> out_emit_pos;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;

RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_MEMBER_EXPR = 21u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMember.uses_status_count != 0u ? min(gHirMember.n, tree_count_status[5u]) : gHirMember.n;
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
           production == PROD_POSTFIX_MEMBER;
}

uint receiver_span_start(uint receiver)
{
    // Calls widen later and member chains run in parallel. Grammar ownership
    // and original token positions establish the start independently of both.
    for (uint depth = 0u; depth < active_node_count() && valid_node(receiver); depth++)
    {
        if (!is_postfix_operator(node_kind[receiver])) return out_emit_pos[receiver];
        uint owner = parent[receiver];
        if (!valid_node(owner)) return INVALID;
        if (is_postfix_operator(node_kind[owner])) receiver = owner;
        else if (hir_is_postfix_sequence_owner(node_kind[owner])) receiver = first_child[owner];
        else return out_emit_pos[receiver];
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID || hir_kind[node] != HIR_MEMBER_EXPR)
        return;

    uint receiver = hir_member_receiver_node[node];
    if (!valid_node(receiver))
        return;

    uint receiver_start = receiver_span_start(receiver);
    uint member_start = hir_token_pos[node];
    if (receiver_start != INVALID &&
        (member_start == INVALID || receiver_start < member_start))
        hir_token_pos[node] = receiver_start;

    uint member_token = hir_member_name_token[node];
    if (member_token != INVALID)
    {
        uint receiver_end_limit = member_token > 0u ? member_token - 1u : INVALID;
        if (receiver_end_limit != INVALID)
        {
            uint receiver_end = hir_token_end[receiver];
            if (receiver_end == INVALID || receiver_end > receiver_end_limit)
                hir_token_end[receiver] = receiver_end_limit;
        }
        // The member expression ends at its own generic argument list, or
        // at its name when it has none. The empty argument list is anchored
        // at the following token, so its span covers that token: for
        // `0..bound.value {` it covered the loop body's `{`, and the member's
        // completion sorted after the body opened.
        uint arguments = first_child[node];
        if (valid_node(arguments))
            hir_token_end[node] = node_kind[arguments] == PROD_MEMBER_TYPE_ARGS_SOME
                ? hir_token_end[arguments] : member_token + 1u;
    }
}
