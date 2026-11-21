import shared.syntax.hir_records;
import shared.collectives.prefix_scan;
import parser.hir.paths.path_tree;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> owner_local_prefix;
StructuredBuffer<uint> owner_block_prefix;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_path_root_owner;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> token_file_id;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirPathSegment> path_segments;
RWStructuredBuffer<uint> canonical_status;

static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint block_count() { return (gCanonical.raw_capacity + WG_SIZE - 1u) / WG_SIZE; }
uint active_count() {
    return gCanonical.uses_status_count != 0u
        ? min(gCanonical.raw_capacity, tree_count_status[5u])
        : gCanonical.raw_capacity;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint root = tid(dtid);
    if (root == 0u)
        family_count[0u] = inclusive_scan_total(block_count(), owner_block_prefix);

    uint active = active_count();
    if (root >= active) return;
    uint owner = path_root_owner(hir_path_root_owner[root]);
    if (owner >= active) return;
    uint block = owner / WG_SIZE;
    uint base = (block == 0u ? 0u : owner_block_prefix[block - 1u]) +
        owner_local_prefix[owner];
    uint ordinal = 0u;
    for (uint raw = path_first_segment(root, active, first_child, node_kind);
         raw < active;
         raw = path_next_segment(raw, active, first_child, next_sibling, node_kind))
    {
        uint row = base + ordinal;
        if (row >= gCanonical.canonical_capacity)
        {
            uint ignored;
            InterlockedMax(canonical_status[0u], 3u, ignored);
            InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        }
        else
        {
            HirPathSegment segment;
            segment.path = owner;
            segment.name_token = hir_token_pos[raw];
            segment.ordinal = ordinal;
            segment.file_id = segment.name_token < gCanonical.canonical_capacity
                ? token_file_id[segment.name_token] : PATH_TREE_INVALID;
            path_segments[row] = segment;
        }
        ++ordinal;
    }
}
