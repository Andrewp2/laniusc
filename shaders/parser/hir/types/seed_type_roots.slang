// Seed topmost type-root ownership, and list the type rows. Nested generic
// argument types link to their direct parser-owned type owner; other HIR type
// nodes are roots.
//
// Only type rows are written, to both ping-pong buffers; the type-root arrays
// are undefined on every other row, and readers test the row's kind first.
// Every link target is itself a type row. Every type row has an owner or a
// link, so the pass marks each type row and counts them per block, in the
// layout of parser/hir/lists/mark_list_rows.slang, and the list
// compaction that follows lists them for the walk. One workgroup covers one
// block of 256 rows; the dispatch covers every block of the tree.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirType;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_application_owner;
RWStructuredBuffer<uint> hir_type_root_link_a;
RWStructuredBuffer<uint> hir_type_root_owner_a;
RWStructuredBuffer<uint> hir_type_root_link_b;
RWStructuredBuffer<uint> hir_type_root_owner_b;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

uint active_node_count()
{
    return gHirType.uses_status_count != 0u
        ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();

    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    if (node < active && hir_kind[node] == HIR_TYPE)
    {
        uint seed = hir_type_arg_owner[node];
        uint parent_type = seed < active ? hir_type_arg_application_owner[seed] : INVALID;
        bool nested = parent_type < active && hir_kind[parent_type] == HIR_TYPE;
        uint link = nested ? parent_type : INVALID;
        uint owner = nested ? INVALID : node;
        hir_type_root_link_a[node] = link;
        hir_type_root_owner_a[node] = owner;
        hir_type_root_link_b[node] = link;
        hir_type_root_owner_b[node] = owner;
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    }
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirType.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
