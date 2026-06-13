// Clear token-indexed call summaries and HIR-indexed call argument slots.
//
// The following publish pass writes call metadata from HIR call records into a
// compact record keyed by callee token. It also scatters parser-owned argument
// rows into a slot table keyed by call HIR node and bounded ordinal so later
// passes do not scan HIR subtrees for arguments.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint4> call_arg_record;
RWStructuredBuffer<uint> call_arg_node;

static const uint INVALID = 0xffffffffu;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.n_tokens)
        call_arg_record[i] = uint4(INVALID, INVALID, INVALID, 0u);

    uint slot_count = gParams.n_hir_nodes * PARAM_CACHE_STRIDE;
    if (i < slot_count)
        call_arg_node[i] = INVALID;
}
