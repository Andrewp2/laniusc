// Seed nearest-match-arm propagation over the raw parse tree.
//
// Pattern nesting is unbounded, so ownership cannot be recovered with a
// grammar-shaped fixed walk. Each lane examines a short local parent span and
// leaves the remaining relation for the shared logarithmic pointer-jump pass.
//
// The relation is read only at pattern nodes (match/arm/links.slang). Every
// node between a pattern and its nearest arm is a pattern or pattern-list
// production (grammar/lanius.bnf, `pattern` and `pattern_tail`), so only
// those nodes walk, and every link they leave points at another such node.
// The pass runs over the match family's rows (hir_match_rank_node), which
// hold every such node; other family rows keep INVALID, and rows outside the
// family are not written.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_match_rank_node;
StructuredBuffer<uint> hir_match_rank_count;

RWStructuredBuffer<uint> hir_semantic_parent_link_a;
RWStructuredBuffer<uint> hir_match_nearest_arm;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u
        ? min(gHirSemantic.n, tree_count_status[5u])
        : gHirSemantic.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool in_pattern_path(uint prod)
{
    return prod == PROD_PATTERN_IDENT || prod == PROD_PATTERN_INT ||
           prod == PROD_PATTERN_TRUE || prod == PROD_PATTERN_FALSE ||
           prod == PROD_PATTERN_TUPLE || prod == PROD_PATTERNS_SOME ||
           prod == PROD_PATTERNS_MORE || prod == PROD_PATTERNS_AFTER_COMMA_MORE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= hir_match_rank_count[0u])
        return;
    uint node = hir_match_rank_node[row];
    if (node >= gHirSemantic.n)
        return;

    hir_semantic_parent_link_a[node] = INVALID;
    hir_match_nearest_arm[node] = INVALID;

    if (!valid_node(node) || !in_pattern_path(node_kind[node]))
        return;

    uint ancestor = parent[node];
    uint local_span = max(1u, gHirSemantic.semantic_parent_local_ancestor_span);
    for (uint hop = 0u; hop < local_span; ++hop)
    {
        if (!valid_node(ancestor) || ancestor == node)
            return;
        uint ancestor_kind = node_kind[ancestor];
        if (ancestor_kind == PROD_MATCH_ARM)
        {
            hir_match_nearest_arm[node] = ancestor;
            return;
        }
        if (!in_pattern_path(ancestor_kind))
            return;
        if (hop + 1u == local_span)
        {
            hir_semantic_parent_link_a[node] = ancestor;
            return;
        }
        uint next = parent[ancestor];
        if (!valid_node(next) || next == ancestor)
            return;
        ancestor = next;
    }
}
