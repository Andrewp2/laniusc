// Seed parser-owned call-argument links from grammar tree records, and list
// the call arguments.
//
// This pass builds the linked list that Pareas-style pointer jumping consumes:
// every non-first argument points at its previous argument, while first
// arguments carry the owning call as the list root seed.
//
// Only call argument rows (hir_call_arg_row) are written; the argument
// arrays are undefined on every other row, except in debug-row mode. The
// pass also marks those rows and counts them per block, in the layout of
// parser/hir/list/rank/prefix_00_local.slang, so the list compaction that
// follows lists them and the later argument passes run over that list only.
// One workgroup covers one block of 256 rows; the dispatch covers every block
// of the tree.

import generated_parse_production_ids;
import hir_family_rows;

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_end;

RWStructuredBuffer<uint> hir_call_arg_end;
RWStructuredBuffer<uint> hir_call_arg_owner_a;
RWStructuredBuffer<uint> hir_call_arg_link_a;
RWStructuredBuffer<uint> hir_call_arg_rank_a;
RWStructuredBuffer<uint> hir_call_arg_owner_b;
RWStructuredBuffer<uint> hir_call_arg_link_b;
RWStructuredBuffer<uint> hir_call_arg_rank_b;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirCall.uses_status_count != 0u ? min(gHirCall.n, tree_count_status[5u]) : gHirCall.n;
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

uint arg_expr_from_container(uint container)
{
    if (!valid_node(container) || !hir_call_arg_container(node_kind[container]))
        return INVALID;
    uint expr = first_child_node(container);
    return valid_node(expr) && hir_kind[expr] == HIR_EXPR ? expr : INVALID;
}

uint previous_arg_for_after_comma_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_ARGS_AFTER_COMMA_MORE)
        return INVALID;

    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return arg_expr_from_container(previous_container);
}

uint owner_seed_for_first_arg_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARGS_SOME)
        return INVALID;
    uint call_node = parent_node(container);
    return valid_node(call_node) && node_kind[call_node] == PROD_POSTFIX_CALL
        ? call_node
        : INVALID;
}

uint end_token_for_arg_expr(uint expr_node)
{
    if (!valid_node(expr_node))
        return INVALID;
    return hir_token_end[expr_node];
}

void seed_argument(uint node, uint container)
{
    hir_call_arg_end[node] = end_token_for_arg_expr(node);
    hir_call_arg_owner_a[node] = INVALID;
    hir_call_arg_link_a[node] = INVALID;
    hir_call_arg_rank_a[node] = 0u;
    hir_call_arg_owner_b[node] = INVALID;
    hir_call_arg_link_b[node] = INVALID;
    hir_call_arg_rank_b[node] = 0u;

    if (node_kind[container] == PROD_ARGS_SOME)
    {
        hir_call_arg_owner_a[node] = owner_seed_for_first_arg_container(container);
        return;
    }

    uint previous = previous_arg_for_after_comma_container(container);
    if (valid_node(previous))
    {
        hir_call_arg_link_a[node] = previous;
        hir_call_arg_rank_a[node] = 1u;
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
    if (node < gHirCall.n && gHirCall.retain_debug_rows != 0u)
        hir_call_arg_end[node] = INVALID;
    if (valid_node(node) && hir_kind[node] == HIR_EXPR)
    {
        uint container = parent_node(node);
        uint container_prod = valid_node(container) ? node_kind[container] : INVALID;
        if (hir_call_arg_row(hir_kind[node], container_prod) &&
            first_child_node(container) == node)
        {
            seed_argument(node, container);
            InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
        }
    }
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirCall.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
