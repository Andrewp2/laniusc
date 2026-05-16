// Derive parser-owned enum variant and match-arm metadata from the tree.
//
// This pass consumes production ids plus the inverted tree arrays. It does not
// inspect token neighborhoods, source bytes, or stdlib names.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirEnumMatch;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_variant_parent_enum;
RWStructuredBuffer<uint> hir_variant_ordinal;
RWStructuredBuffer<uint> hir_variant_payload_start;
RWStructuredBuffer<uint> hir_variant_payload_count;
RWStructuredBuffer<uint> hir_match_scrutinee_node;
RWStructuredBuffer<uint> hir_match_arm_start;
RWStructuredBuffer<uint> hir_match_arm_count;
RWStructuredBuffer<uint> hir_match_arm_pattern_node;
RWStructuredBuffer<uint> hir_match_arm_payload_start;
RWStructuredBuffer<uint> hir_match_arm_payload_count;
RWStructuredBuffer<uint> hir_match_arm_result_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;
static const uint HIR_TYPE = 5u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirEnumMatch.uses_ll1 != 0u ? min(gHirEnumMatch.n, ll1_status[5u])
                                        : gHirEnumMatch.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = i + 1u;
    return valid_node(child) && parent[child] == i ? child : INVALID;
}

uint next_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint sibling = subtree_end[i];
    return valid_node(sibling) && parent[sibling] == parent[i] ? sibling : INVALID;
}

bool is_pattern_production(uint prod)
{
    return prod == PROD_PATTERN_IDENT || prod == PROD_PATTERN_INT || prod == PROD_PATTERN_TRUE ||
           prod == PROD_PATTERN_FALSE;
}

uint ancestor_with_production(uint i, uint prod)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p))
            return INVALID;
        if (node_kind[p] == prod)
            return p;
        cur = p;
    }
    return INVALID;
}

uint nearest_pattern_ancestor_before(uint i, uint stop)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p) || p == stop)
            return INVALID;
        if (is_pattern_production(node_kind[p]))
            return p;
        cur = p;
    }
    return INVALID;
}

bool has_hir_type_ancestor_before(uint i, uint stop)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        uint p = parent[cur];
        if (!valid_node(p) || p == stop)
            return false;
        if (hir_kind[p] == HIR_TYPE)
            return true;
        cur = p;
    }
    return false;
}

void clear_fields(uint i)
{
    hir_variant_parent_enum[i] = INVALID;
    hir_variant_ordinal[i] = INVALID;
    hir_variant_payload_start[i] = INVALID;
    hir_variant_payload_count[i] = 0u;
    hir_match_scrutinee_node[i] = INVALID;
    hir_match_arm_start[i] = INVALID;
    hir_match_arm_count[i] = 0u;
    hir_match_arm_pattern_node[i] = INVALID;
    hir_match_arm_payload_start[i] = INVALID;
    hir_match_arm_payload_count[i] = 0u;
    hir_match_arm_result_node[i] = INVALID;
}

void publish_enum_variant(uint i)
{
    uint enum_i = ancestor_with_production(i, PROD_ENUM);
    if (!valid_node(enum_i))
        return;

    uint ordinal = 0u;
    [loop]
    for (uint j = 0u; j < i; j += 1u)
    {
        if (valid_node(j) && node_kind[j] == PROD_ENUM_VARIANT &&
            ancestor_with_production(j, PROD_ENUM) == enum_i)
            ordinal += 1u;
    }

    uint first_payload = INVALID;
    uint payload_count = 0u;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (hir_kind[j] == HIR_TYPE && !has_hir_type_ancestor_before(j, i))
        {
            if (first_payload == INVALID)
                first_payload = j;
            payload_count += 1u;
        }
    }

    hir_variant_parent_enum[i] = enum_i;
    hir_variant_ordinal[i] = ordinal;
    hir_variant_payload_start[i] = first_payload;
    hir_variant_payload_count[i] = payload_count;
}

void publish_match_expr(uint i)
{
    hir_match_scrutinee_node[i] = first_child_node(i);

    uint first_arm = INVALID;
    uint arm_count = 0u;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (node_kind[j] == PROD_MATCH_ARM &&
            ancestor_with_production(j, PROD_MATCH_EXPR) == i)
        {
            if (first_arm == INVALID)
                first_arm = j;
            arm_count += 1u;
        }
    }

    hir_match_arm_start[i] = first_arm;
    hir_match_arm_count[i] = arm_count;
}

void publish_match_arm(uint i)
{
    uint pattern = first_child_node(i);
    if (!valid_node(pattern))
        return;

    uint result = INVALID;
    uint arm_end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < arm_end; j += 1u)
    {
        if (hir_kind[j] == HIR_EXPR)
        {
            result = j;
            break;
        }
    }

    uint first_payload = INVALID;
    uint payload_count = 0u;
    uint end = min(subtree_end[pattern], active_node_count());
    [loop]
    for (uint j = pattern + 1u; j < end; j += 1u)
    {
        if (is_pattern_production(node_kind[j]) &&
            nearest_pattern_ancestor_before(j, i) == pattern)
        {
            if (first_payload == INVALID)
                first_payload = j;
            payload_count += 1u;
        }
    }

    hir_match_arm_pattern_node[i] = pattern;
    hir_match_arm_payload_start[i] = first_payload;
    hir_match_arm_payload_count[i] = payload_count;
    hir_match_arm_result_node[i] = valid_node(result) ? result : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirEnumMatch.n)
        return;

    clear_fields(i);

    if (!valid_node(i))
        return;

    uint prod = node_kind[i];
    if (prod == PROD_ENUM_VARIANT)
        publish_enum_variant(i);
    else if (prod == PROD_MATCH_EXPR)
        publish_match_expr(i);
    else if (prod == PROD_MATCH_ARM)
        publish_match_arm(i);
}
