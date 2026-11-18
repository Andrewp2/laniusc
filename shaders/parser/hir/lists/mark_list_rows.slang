// Mark owner/link-seeded HIR list nodes and count them per block.
//
// This generic pass is used for single-list pointer-jump families where the
// seed pass has already written owner/link records. It consumes those records
// directly rather than rediscovering list membership from grammar productions.
//
// The marks are one bit per node: word w of hir_list_rank_flag holds nodes
// 32w to 32w + 31, so block b owns words 8b to 8b + 7. The words of a whole
// tree stay in L2, where the compact scatter reads them back; per-node flag
// and local-prefix rows would stream two tree-sized arrays through DRAM.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirList;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_list_owner_a;
StructuredBuffer<uint> hir_list_link_a;

RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirList.uses_status_count != 0u ? min(gHirList.n, tree_count_status[5u])
                                   : gHirList.n;
}

bool valid_node(uint node, uint active)
{
    return node != INVALID && node < active;
}

uint list_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    return valid_node(hir_list_owner_a[node], active) ||
           valid_node(hir_list_link_a[node], active)
        ? 1u
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();

    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    if (list_rank_flag(node, active) != 0u)
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirList.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
