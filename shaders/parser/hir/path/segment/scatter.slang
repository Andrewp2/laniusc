// Finalize canonical path segment counts from pointer-jumped owner/ordinal rows.

import atomics;
import generated_parse_production_ids;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirPath;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_path_segment_owner_a;
StructuredBuffer<uint> hir_path_segment_rank_a;
RWStructuredBuffer<uint> hir_path_segment_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirPath.uses_status_count != 0u ? min(gHirPath.n, tree_count_status[5u]) : gHirPath.n; }
bool valid_node(uint node) { return node != INVALID && node < active_node_count(); }
bool is_path_segment(uint prod)
{
    return prod == PROD_PATH_IDENT || prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_TYPE_PATH_IDENT || prod == PROD_BOUND_TYPE_PATH_IDENT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || !is_path_segment(node_kind[node]))
        return;
    uint owner = hir_path_segment_owner_a[node];
    if (!valid_node(owner))
        return;
    atomic_u32_max(hir_path_segment_count, owner, hir_path_segment_rank_a[node] + 1u);
}
