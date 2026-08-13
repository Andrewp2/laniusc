import hir_records;
import prefix_scan;
import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> owner_local_prefix;
StructuredBuffer<uint> owner_block_prefix;
StructuredBuffer<uint> path_segment_owner;
StructuredBuffer<uint> path_segment_rank;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirPathSegment> path_segments;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint block_count() { return (gCanonical.raw_capacity + WG_SIZE - 1u) / WG_SIZE; }
uint active_count() {
    return gCanonical.uses_status_count != 0u
        ? min(gCanonical.raw_capacity, tree_count_status[5u])
        : gCanonical.raw_capacity;
}
bool path_segment(uint production) {
    return production == PROD_PATH_IDENT || production == PROD_PATH_IDENT_ARGS ||
           production == PROD_TYPE_PATH_IDENT || production == PROD_BOUND_TYPE_PATH_IDENT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), owner_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= active_count() || !path_segment(node_kind[raw])) return;

    uint owner = path_segment_owner[raw];
    if (owner >= active_count()) return;
    uint block = owner / WG_SIZE;
    uint base = (block == 0u ? 0u : owner_block_prefix[block - 1u]) +
        owner_local_prefix[owner];
    uint row = base + path_segment_rank[raw];
    if (row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    HirPathSegment segment;
    segment.path = owner;
    segment.name_token = hir_token_pos[raw];
    segment.ordinal = path_segment_rank[raw];
    segment.file_id = hir_token_file_id[raw];
    path_segments[row] = segment;
}
