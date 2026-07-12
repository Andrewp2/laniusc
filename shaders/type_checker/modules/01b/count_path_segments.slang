// Project parser-owned path segment counts onto compact typechecker path rows.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> hir_path_segment_count;
RWStructuredBuffer<uint> path_segment_count;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_node_count() { return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]); }
uint active_path_count() { return min(path_count_out[0], gParams.n_hir_nodes); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_slot = linear_thread_id(dtid);
    if (path_slot >= active_path_count())
        return;
    uint owner = path_owner_hir[path_slot];
    path_segment_count[path_slot] = owner < active_hir_node_count()
        ? hir_path_segment_count[owner] : 0u;
}
