// Mark match arm/pattern-payload nodes and count them per block.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMatch;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;

RWStructuredBuffer<uint> hir_match_rank_flag;
RWStructuredBuffer<uint> hir_match_rank_block_sum;

// One mark bit per node, in the layout of
// parser/hir/list/rank/prefix_00_local.slang.
static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirMatch.uses_status_count != 0u ? min(gHirMatch.n, tree_count_status[5u])
                                    : gHirMatch.n;
}

bool is_pattern_production(uint prod)
{
    return prod == PROD_PATTERN_IDENT || prod == PROD_PATTERN_INT ||
           prod == PROD_PATTERN_TRUE || prod == PROD_PATTERN_FALSE;
}

uint match_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    uint prod = node_kind[node];
    return prod == PROD_MATCH_ARM || is_pattern_production(prod) ? 1u : 0u;
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

    if (match_rank_flag(node, active) != 0u)
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirMatch.n + 31u) / 32u)
        hir_match_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_match_rank_block_sum[block_i] = total;
    }
}
