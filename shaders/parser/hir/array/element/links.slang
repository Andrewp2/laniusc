// Seed array literal element links from grammar tree records, and list the
// array elements.
//
// Array element lists are right-recursive: first elements seed the owning array
// literal, and later elements point at their previous element. A separate
// pointer-jump pass computes ordinals and owners.
//
// Only array element rows (hir_array_element_row) are written; the element
// arrays are undefined on every other row, except in debug-row mode. The pass also marks those rows and
// counts them per block, in the layout of parser/hir/list/rank/
// prefix_00_local.slang, so the list compaction that follows lists them and
// the rank step and scatter run over that list only. One workgroup covers one
// block of 256 rows; the dispatch covers every block of the tree.

import generated_parse_production_ids;
import hir_family_rows;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirArray;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_array_element_owner_a;
RWStructuredBuffer<uint> hir_array_element_link_a;
RWStructuredBuffer<uint> hir_array_element_rank_a;
RWStructuredBuffer<uint> hir_array_element_previous;
RWStructuredBuffer<uint> hir_array_element_owner_b;
RWStructuredBuffer<uint> hir_array_element_link_b;
RWStructuredBuffer<uint> hir_array_element_rank_b;
RWStructuredBuffer<uint> hir_array_lit_first_element;
RWStructuredBuffer<uint> hir_array_lit_element_count;
RWStructuredBuffer<uint> hir_array_element_parent_lit;
RWStructuredBuffer<uint> hir_array_element_ordinal;
RWStructuredBuffer<uint> hir_array_element_next;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ARRAY_EXPR = 24u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirArray.uses_status_count != 0u ? min(gHirArray.n, tree_count_status[5u])
                                    : gHirArray.n;
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

uint element_from_container(uint container)
{
    if (!valid_node(container) || !hir_array_element_container(node_kind[container]))
        return INVALID;
    uint expr = first_child_node(container);
    return valid_node(expr) && hir_family_expr_kind(hir_kind[expr]) ? expr : INVALID;
}

uint previous_element_for_after_comma(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARRAY_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return element_from_container(previous_container);
}

uint owner_seed_for_array_element_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARRAY_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && hir_kind[owner] == HIR_ARRAY_EXPR ? owner : INVALID;
}

void seed_element(uint node, uint container_prod, uint container)
{
    hir_array_element_owner_a[node] = INVALID;
    hir_array_element_link_a[node] = INVALID;
    hir_array_element_rank_a[node] = 0u;
    hir_array_element_previous[node] = INVALID;
    hir_array_element_owner_b[node] = INVALID;
    hir_array_element_link_b[node] = INVALID;
    hir_array_element_rank_b[node] = 0u;
    hir_array_element_parent_lit[node] = INVALID;
    hir_array_element_ordinal[node] = INVALID;

    if (container_prod == PROD_ARRAY_SOME)
    {
        hir_array_element_owner_a[node] =
            owner_seed_for_array_element_container(container);
        return;
    }

    uint previous = previous_element_for_after_comma(container);
    if (valid_node(previous))
    {
        hir_array_element_link_a[node] = previous;
        hir_array_element_rank_a[node] = 1u;
        hir_array_element_previous[node] = previous;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;

    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    // Debug readbacks read every row; the compile path never retains them.
    if (node < gHirArray.n && gHirArray.retain_debug_rows != 0u)
    {
        hir_array_lit_first_element[node] = INVALID;
        hir_array_lit_element_count[node] = 0u;
        hir_array_element_next[node] = INVALID;
        hir_array_element_parent_lit[node] = INVALID;
        hir_array_element_ordinal[node] = INVALID;
    }
    if (valid_node(node) && hir_family_expr_kind(hir_kind[node]))
    {
        uint container = parent_node(node);
        uint container_prod = valid_node(container) ? node_kind[container] : INVALID;
        if (hir_array_element_container(container_prod))
        {
            seed_element(node, container_prod, container);
            InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
        }
    }
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirArray.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
