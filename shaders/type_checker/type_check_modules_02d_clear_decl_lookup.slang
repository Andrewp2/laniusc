// GPU declaration lookup clear.
//
// Scheduling contract:
// - Dispatch before type_check_modules_02d_scatter_decl_span_records.slang.
// - This pass clears token-indexed declaration-row lookup records so later
//   semantic/backend consumers can resolve declaration tokens without scanning
//   dense declaration tables.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> decl_id_by_name_token;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    decl_id_by_name_token[i] = INVALID;
}
