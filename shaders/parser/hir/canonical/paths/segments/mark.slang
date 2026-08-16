// Compute owner-grouped bases for compact path segments. Source-order
// compaction cannot keep an outer path contiguous when a generic argument
// contains a nested path, so the scan is weighted by each raw owner's segment
// count and the scatter appends owner-local ordinals to that base.

import prefix_scan;
import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; uint records_use_token_rows; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> segment_count_by_owner;
RWStructuredBuffer<uint> owner_local_prefix;
RWStructuredBuffer<uint> owner_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

uint group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_count() {
    return gCanonical.uses_status_count != 0u
        ? min(gCanonical.raw_capacity, tree_count_status[5u])
        : gCanonical.raw_capacity;
}
bool is_path_owner(uint raw) {
    uint kind = hir_kind[raw];
    return (kind == HIR_PATH_EXPR && node_kind[raw] == PROD_PATH) ||
        kind == HIR_TYPE || node_kind[raw] == PROD_BOUND_TYPE_IDENT ||
        kind == HIR_MODULE_ITEM || kind == HIR_IMPORT_ITEM;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint block = group_id(gid);
    uint lane = ltid.x;
    uint raw = block * WG_SIZE + lane;
    bool owner = raw < active_count() && is_path_owner(raw);
    uint owner_row = gCanonical.records_use_token_rows != 0u && owner
        ? hir_token_pos[raw]
        : raw;
    uint owner_capacity = gCanonical.records_use_token_rows != 0u
        ? gCanonical.canonical_capacity
        : gCanonical.raw_capacity;
    uint value = owner && owner_row < owner_capacity
        ? segment_count_by_owner[owner_row]
        : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);
    if (raw < gCanonical.raw_capacity)
        owner_local_prefix[raw] = inclusive - value;
    if (lane == WG_SIZE - 1u)
        owner_block_sum[block] = inclusive;
}
