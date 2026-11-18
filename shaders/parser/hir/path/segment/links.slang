// Seed the path segments' walk records, and list the path segments: a
// segment under an owned path root takes that owner, a segment in a path tail
// links to the previous segment with rank 1, and any other segment is an
// empty record.
//
// Only path segment rows are written, to both ping-pong buffers; the segment
// arrays are undefined on every other row. The pass also marks the segments
// and counts them per block, in the layout of parser/hir/list/rank/
// prefix_00_local.slang, so the list compaction that follows lists them and
// the walk and the scatter run over that list only. A segment's link is
// always another segment. One workgroup covers one block of 256 rows; the
// dispatch covers every block of the tree.

import generated_parse_production_ids;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirPath;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_path_root_owner;

RWStructuredBuffer<uint> hir_path_segment_owner_a;
RWStructuredBuffer<uint> hir_path_segment_link_a;
RWStructuredBuffer<uint> hir_path_segment_rank_a;
RWStructuredBuffer<uint> hir_path_segment_owner_b;
RWStructuredBuffer<uint> hir_path_segment_link_b;
RWStructuredBuffer<uint> hir_path_segment_rank_b;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint INVALID = 0xffffffffu;
static const uint OWNER_NODE_MASK = 0x7fffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gHirPath.uses_status_count != 0u ? min(gHirPath.n, tree_count_status[5u]) : gHirPath.n; }
bool valid_node(uint node) { return node != INVALID && node < active_node_count(); }
bool is_path_segment(uint prod)
{
    return prod == PROD_PATH_IDENT || prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_TYPE_PATH_IDENT || prod == PROD_BOUND_TYPE_PATH_IDENT ||
           prod == PROD_ARRAY_LENGTH_PATH_IDENT || prod == PROD_CAST_TYPE_PATH_IDENT;
}
bool is_path_tail(uint prod)
{
    return prod == PROD_PATH_MORE || prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH_MORE || prod == PROD_ARRAY_LENGTH_PATH_MORE ||
           prod == PROD_CAST_TYPE_PATH_MORE;
}

void seed_segment(uint node)
{
    uint owner = INVALID;
    uint link = INVALID;
    uint rank = 0u;
    uint container = parent[node];
    if (valid_node(container))
    {
        uint encoded_owner = hir_path_root_owner[container];
        if (encoded_owner != 0u)
        {
            uint root_owner = (encoded_owner & OWNER_NODE_MASK) - 1u;
            owner = valid_node(root_owner) ? root_owner : INVALID;
        }
        else if (is_path_tail(node_kind[container]))
        {
            uint previous = prev_sibling[container];
            if (valid_node(previous) && is_path_segment(node_kind[previous]))
            {
                link = previous;
                rank = 1u;
            }
        }
    }

    hir_path_segment_owner_a[node] = owner;
    hir_path_segment_link_a[node] = link;
    hir_path_segment_rank_a[node] = rank;
    hir_path_segment_owner_b[node] = owner;
    hir_path_segment_link_b[node] = link;
    hir_path_segment_rank_b[node] = rank;
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

    if (valid_node(node) && is_path_segment(node_kind[node]))
    {
        seed_segment(node);
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    }
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirPath.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
