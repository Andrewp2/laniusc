// Mark canonical string HIR nodes, one bit per node, and count them per block.
// The bit layout is that of parser/hir/lists/mark_list_rows.slang.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_record;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR_STRING = 28u;
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gHirString.uses_status_count != 0u ? min(gHirString.n, tree_count_status[5u]) : gHirString.n; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block * WG_SIZE + lane;
    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();
    if (node < active_node_count() && hir_expr_record[node * 4u] == HIR_EXPR_STRING)
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    GroupMemoryBarrierWithGroupSync();
    uint word_i = block * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirString.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block] = total;
    }
}
