// Derive parser-owned member expression metadata from the inverted tree.
//
// This pass records the receiver and selected member name for each
// PROD_POSTFIX_MEMBER node. Downstream semantic passes consume these HIR
// records instead of guessing from neighboring tokens.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirMember;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;

RWStructuredBuffer<uint> hir_member_receiver_node;
RWStructuredBuffer<uint> hir_member_receiver_token;
RWStructuredBuffer<uint> hir_member_name_token;

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
    return gHirMember.uses_ll1 != 0u ? min(gHirMember.n, ll1_status[5u]) : gHirMember.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint first_child_node(uint node)
{
    uint child = valid_node(node) ? first_child[node] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint node_end(uint node)
{
    if (!valid_node(node))
        return INVALID;
    return min(subtree_end[node], active_node_count());
}

bool has_ancestor_node(uint node, uint ancestor)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        if (cur == ancestor)
            return true;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return false;
        cur = p;
    }
    return false;
}

uint ancestor_with_production(uint node, uint prod)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (node_kind[cur] == prod)
            return cur;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

bool is_postfix_operator(uint prod)
{
    return prod == PROD_POSTFIX_CALL || prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER || prod == PROD_POSTFIX_INC ||
           prod == PROD_POSTFIX_DEC;
}

bool is_name_value_production(uint prod)
{
    return prod == PROD_IDENT || prod == PROD_IDENT_PLAIN || prod == PROD_PATH ||
           prod == PROD_SELF_VALUE;
}

bool is_member_name_production(uint prod)
{
    return prod == PROD_IDENT || prod == PROD_IDENT_PLAIN;
}

uint first_descendant_token_with_kind(uint root, bool want_member_name)
{
    if (!valid_node(root))
        return INVALID;

    uint end = node_end(root);
    [loop]
    for (uint node = root; node < end; node += 1u)
    {
        uint prod = node_kind[node];
        bool ok = want_member_name ? is_member_name_production(prod)
                                   : is_name_value_production(prod);
        if (ok)
        {
            uint token = hir_token_pos[node];
            if (token != INVALID)
                return token;
        }
    }
    return INVALID;
}

uint member_name_token_for_node(uint member_node)
{
    uint start = valid_node(member_node) ? hir_token_pos[member_node] : INVALID;
    uint end = valid_node(member_node) ? hir_token_end[member_node] : INVALID;
    uint child = first_child_node(member_node);
    uint child_token = valid_node(child) ? hir_token_pos[child] : INVALID;
    if (start != INVALID && end != INVALID && child_token != INVALID &&
        child_token > start && child_token <= end)
        return child_token - 1u;
    if (start != INVALID && end != INVALID && end >= 1u && end - 1u > start)
        return end - 1u;
    if (start != INVALID && end != INVALID && end >= 2u && end - 2u > start)
        return end - 2u;
    if (start != INVALID && end != INVALID && start + 1u < end)
        return start + 1u;
    return first_descendant_token_with_kind(member_node, true);
}

uint previous_postfix_operator(uint postfix_node, uint member_node)
{
    if (!valid_node(postfix_node) || !valid_node(member_node))
        return INVALID;

    uint previous = INVALID;
    uint end = min(member_node, node_end(postfix_node));
    [loop]
    for (uint node = postfix_node + 1u; node < end; node += 1u)
    {
        if (!has_ancestor_node(node, postfix_node))
            continue;
        if (is_postfix_operator(node_kind[node]))
            previous = node;
    }
    return previous;
}

uint postfix_base_token(uint postfix_node)
{
    uint base = valid_node(postfix_node) ? first_child_node(postfix_node) : INVALID;
    return first_descendant_token_with_kind(base, false);
}

uint postfix_operator_head_token(uint operator_node)
{
    uint postfix_node = ancestor_with_production(operator_node, PROD_POSTFIX);
    uint previous = previous_postfix_operator(postfix_node, operator_node);
    if (valid_node(previous) && node_kind[previous] == PROD_POSTFIX_MEMBER)
        return member_name_token_for_node(previous);
    if (valid_node(previous) && node_kind[previous] == PROD_POSTFIX_CALL)
        return hir_token_pos[previous] > 0u ? hir_token_pos[previous] - 1u : INVALID;
    return postfix_base_token(postfix_node);
}

uint receiver_token_for_node(uint receiver_node)
{
    if (!valid_node(receiver_node))
        return INVALID;
    if (node_kind[receiver_node] == PROD_POSTFIX_MEMBER || hir_kind[receiver_node] == HIR_MEMBER_EXPR)
        return member_name_token_for_node(receiver_node);
    if (is_postfix_operator(node_kind[receiver_node]))
        return postfix_operator_head_token(receiver_node);
    return first_descendant_token_with_kind(receiver_node, false);
}

uint receiver_node_for_member(uint member_node)
{
    uint postfix_node = ancestor_with_production(member_node, PROD_POSTFIX);
    if (!valid_node(postfix_node))
        return INVALID;

    uint previous = previous_postfix_operator(postfix_node, member_node);
    if (valid_node(previous))
        return previous;

    uint base = first_child_node(postfix_node);
    return valid_node(base) ? base : INVALID;
}

void clear_member(uint node)
{
    hir_member_receiver_node[node] = INVALID;
    hir_member_receiver_token[node] = INVALID;
    hir_member_name_token[node] = INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirMember.n)
        return;

    clear_member(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return;

    uint receiver = receiver_node_for_member(node);
    uint receiver_token = receiver_token_for_node(receiver);
    uint member_token = member_name_token_for_node(node);
    if (receiver_token == INVALID || member_token == INVALID)
        return;

    hir_member_receiver_node[node] = receiver;
    hir_member_receiver_token[node] = receiver_token;
    hir_member_name_token[node] = member_token;
}
