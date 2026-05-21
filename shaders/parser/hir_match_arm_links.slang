// Seed match-arm and match-pattern-payload links from grammar tree records.
//
// Match arm lists and tuple-pattern payload lists are right-recursive. First
// entries seed the owning match/arm, and later entries point at their previous
// sibling. A separate pointer-jump pass computes owners and ordinals.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirMatch;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_match_scrutinee_node;
RWStructuredBuffer<uint> hir_match_arm_pattern_node;
RWStructuredBuffer<uint> hir_match_arm_result_node;
RWStructuredBuffer<uint> hir_match_arm_owner_a;
RWStructuredBuffer<uint> hir_match_arm_link_a;
RWStructuredBuffer<uint> hir_match_arm_rank_a;
RWStructuredBuffer<uint> hir_match_arm_previous;
RWStructuredBuffer<uint> hir_match_payload_owner_a;
RWStructuredBuffer<uint> hir_match_payload_link_a;
RWStructuredBuffer<uint> hir_match_payload_rank_a;
RWStructuredBuffer<uint> hir_match_arm_owner_b;
RWStructuredBuffer<uint> hir_match_arm_link_b;
RWStructuredBuffer<uint> hir_match_arm_rank_b;
RWStructuredBuffer<uint> hir_match_payload_owner_b;
RWStructuredBuffer<uint> hir_match_payload_link_b;
RWStructuredBuffer<uint> hir_match_payload_rank_b;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMatch.uses_ll1 != 0u ? min(gHirMatch.n, ll1_status[5u])
                                    : gHirMatch.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent[sibling] == parent[node]
        ? sibling
        : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = prev_sibling[node];
    return valid_node(sibling) && parent[sibling] == parent[node]
        ? sibling
        : INVALID;
}

bool is_pattern_production(uint prod)
{
    return prod == PROD_PATTERN_IDENT || prod == PROD_PATTERN_INT ||
           prod == PROD_PATTERN_TRUE || prod == PROD_PATTERN_FALSE;
}

bool is_match_arm_container(uint prod)
{
    return prod == PROD_MATCH_ARMS_SOME ||
           prod == PROD_MATCH_ARMS_AFTER_COMMA_MORE;
}

uint arm_from_container(uint container)
{
    if (!valid_node(container) || !is_match_arm_container(node_kind[container]))
        return INVALID;
    uint arm = first_child_node(container);
    return valid_node(arm) && node_kind[arm] == PROD_MATCH_ARM ? arm : INVALID;
}

uint first_arm_from_match_expr(uint match_node)
{
    if (!valid_node(match_node) || node_kind[match_node] != PROD_MATCH_EXPR)
        return INVALID;
    uint scrutinee = first_child_node(match_node);
    uint arms = next_sibling_node(scrutinee);
    return arm_from_container(arms);
}

uint previous_arm_from_tail_sibling(uint more)
{
    uint previous = previous_sibling_node(more);
    uint previous_prod = valid_node(previous) ? node_kind[previous] : INVALID;
    if (is_match_arm_container(previous_prod))
        return arm_from_container(previous);
    if (previous_prod == PROD_MATCH_ARMS_AFTER_COMMA_MORE)
        return arm_from_container(previous);
    if (previous_prod == PROD_MATCH_EXPR)
        return first_arm_from_match_expr(previous);
    return INVALID;
}

uint previous_arm_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_MATCH_ARMS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    uint previous = arm_from_container(previous_container);
    return valid_node(previous) ? previous : previous_arm_from_tail_sibling(more);
}

uint owner_seed_for_arm_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_MATCH_ARMS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_MATCH_EXPR
        ? owner
        : INVALID;
}

bool is_pattern_payload_container(uint prod)
{
    return prod == PROD_PATTERNS_SOME ||
           prod == PROD_PATTERNS_AFTER_COMMA_MORE;
}

uint payload_pattern_from_container(uint container)
{
    if (!valid_node(container) || !is_pattern_payload_container(node_kind[container]))
        return INVALID;
    uint pattern = first_child_node(container);
    return valid_node(pattern) && is_pattern_production(node_kind[pattern])
        ? pattern
        : INVALID;
}

uint previous_payload_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_PATTERNS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return payload_pattern_from_container(previous_container);
}

uint owner_pattern_for_payload_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_PATTERNS_SOME)
        return INVALID;
    uint tuple_tail = parent_node(container);
    uint owner_pattern = parent_node(tuple_tail);
    return valid_node(owner_pattern) &&
            is_pattern_production(node_kind[owner_pattern])
        ? owner_pattern
        : INVALID;
}

uint owner_seed_for_payload_container(uint container)
{
    uint owner_pattern = owner_pattern_for_payload_container(container);
    uint arm = parent_node(owner_pattern);
    return valid_node(arm) && node_kind[arm] == PROD_MATCH_ARM ? arm : INVALID;
}

void publish_match_expr_direct(uint node)
{
    uint scrutinee = first_child_node(node);
    if (valid_node(scrutinee) && hir_kind[scrutinee] == HIR_EXPR)
        hir_match_scrutinee_node[node] = scrutinee;
}

void seed_match_arm(uint node)
{
    uint pattern = first_child_node(node);
    if (valid_node(pattern) && is_pattern_production(node_kind[pattern]))
        hir_match_arm_pattern_node[node] = pattern;

    uint result = next_sibling_node(pattern);
    if (valid_node(result) && hir_kind[result] == HIR_EXPR)
        hir_match_arm_result_node[node] = result;

    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    if (prod == PROD_MATCH_ARMS_SOME)
    {
        hir_match_arm_owner_a[node] = owner_seed_for_arm_container(container);
        return;
    }

    if (prod == PROD_MATCH_ARMS_AFTER_COMMA_MORE)
    {
        uint previous = previous_arm_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_match_arm_link_a[node] = previous;
            hir_match_arm_rank_a[node] = 1u;
            hir_match_arm_previous[node] = previous;
        }
    }
}

void seed_payload_pattern(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    if (prod == PROD_PATTERNS_SOME)
    {
        hir_match_payload_owner_a[node] =
            owner_seed_for_payload_container(container);
        return;
    }

    if (prod == PROD_PATTERNS_AFTER_COMMA_MORE)
    {
        uint previous = previous_payload_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_match_payload_link_a[node] = previous;
            hir_match_payload_rank_a[node] = 1u;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirMatch.n)
        return;

    hir_match_arm_owner_a[node] = INVALID;
    hir_match_arm_link_a[node] = INVALID;
    hir_match_arm_rank_a[node] = 0u;
    hir_match_arm_previous[node] = INVALID;
    hir_match_payload_owner_a[node] = INVALID;
    hir_match_payload_link_a[node] = INVALID;
    hir_match_payload_rank_a[node] = 0u;
    hir_match_arm_owner_b[node] = INVALID;
    hir_match_arm_link_b[node] = INVALID;
    hir_match_arm_rank_b[node] = 0u;
    hir_match_payload_owner_b[node] = INVALID;
    hir_match_payload_link_b[node] = INVALID;
    hir_match_payload_rank_b[node] = 0u;

    if (!valid_node(node))
        return;

    uint prod = node_kind[node];
    if (prod == PROD_MATCH_EXPR)
        publish_match_expr_direct(node);
    else if (prod == PROD_MATCH_ARM)
        seed_match_arm(node);
    else if (is_pattern_production(prod))
        seed_payload_pattern(node);
}
