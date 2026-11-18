import generated_parse_production_ids;
// Seed each payload type's walk to its enclosing enum variant, and list the
// rows the walk steps over.
//
// Only the family's rows are written, to both ping-pong buffers: enum
// variants, payload types and the variant-field chains between them. The
// owner arrays are undefined on every other row. A row links only to another
// family row, so the walk never reads an unwritten row. The pass also marks
// the rows with an owner or a link and counts them per block, in the layout
// of parser/hir/list/rank/prefix_00_local.slang, so the list compaction that
// follows lists them for the walk. One workgroup covers one block of 256
// rows; the dispatch covers every block of the tree.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> candidate_raw_by_anchor;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> owner_link_a;
RWStructuredBuffer<uint> owner_value_a;
RWStructuredBuffer<uint> owner_link_b;
RWStructuredBuffer<uint> owner_value_b;
static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;
static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint raw) { return raw != INVALID && raw < active_count(); }
bool variant_node(uint raw) { return valid(raw) && node_kind[raw] == PROD_ENUM_VARIANT; }
bool payload_candidate(uint raw)
{
    if (!valid(raw) || hir_kind[raw] != HIR_TYPE) return false;
    uint p = parent[raw];
    if (!valid(p)) return false;
    uint production = node_kind[p];
    return production == PROD_ENUM_VARIANT_FIELDS_SOME ||
           production == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE;
}

// Productions between a payload type and its enum variant:
// enum_variant -> enum_variant_tuple -> fields_some -> (fields_more ->
// after_comma_more)*. Only these nodes and the payload types link to their
// parents, so the owner walk steps over payload chains instead of the whole
// tree.
bool payload_chain_node(uint raw)
{
    uint production = node_kind[raw];
    return production == PROD_ENUM_VARIANT_TUPLE ||
           production == PROD_ENUM_VARIANT_FIELDS_SOME ||
           production == PROD_ENUM_VARIANT_FIELDS_MORE ||
           production == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE;
}

// Writes the row's owner record when it is a family row; returns whether the
// walk steps over it.
bool seed_owner(uint raw)
{
    bool candidate = payload_candidate(raw);
    if (candidate)
    {
        uint anchor = hir_token_pos[raw];
        if (anchor < gCanonical.canonical_capacity)
        {
            uint ignored;
            InterlockedMax(candidate_raw_by_anchor[anchor], raw + 1u, ignored);
            InterlockedMax(family_flag[anchor], 1u, ignored);
        }
    }
    bool variant = variant_node(raw);
    if (!variant && !candidate && !payload_chain_node(raw))
        return false;
    uint link = INVALID;
    uint value = INVALID;
    if (variant)
    {
        value = raw;
    }
    else
    {
        uint ancestor = parent[raw];
        // A link to a row outside the family would end the walk with no
        // owner, as an empty record does.
        if (valid(ancestor) && ancestor != raw)
        {
            if (variant_node(ancestor))
                value = ancestor;
            else if (payload_chain_node(ancestor))
                link = ancestor;
        }
    }
    owner_link_a[raw] = link;
    owner_value_a[raw] = value;
    owner_link_b[raw] = link;
    owner_value_b[raw] = value;
    return link != INVALID || value != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint raw = block_i * WG_SIZE + lane;

    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    if (valid(raw) && seed_owner(raw))
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gCanonical.raw_capacity + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
