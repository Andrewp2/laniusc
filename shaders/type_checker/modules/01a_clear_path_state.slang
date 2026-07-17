// Initialize path state before compact path rows are scattered.
//
// This must be a separate dispatch. Clearing the owner map in the scatter
// dispatch races with other workgroups publishing path ids for those owners.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> path_id_by_owner_hir;
RWStructuredBuffer<uint> path_max_segment_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    if (row < gParams.n_hir_nodes)
        path_id_by_owner_hir[row] = INVALID;
    if (row == 0u)
        path_max_segment_count[0u] = 0u;
}
