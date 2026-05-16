// Clear token-indexed parser-owned call argument records.
//
// The following publish pass writes call metadata from HIR call records into a
// compact table keyed by callee token and argument ordinal. Consumers bind this
// one table instead of rediscovering call syntax or binding every HIR call
// array directly.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint4> call_arg_record;

static const uint INVALID = 0xffffffffu;
static const uint PARAM_CACHE_STRIDE = 16u;
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
    if (i >= gParams.n_tokens * PARAM_CACHE_STRIDE)
        return;

    call_arg_record[i] = uint4(INVALID, INVALID, INVALID, 0u);
}
