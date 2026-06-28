// Clear resident visible-name/type outputs used by the HIR declaration table path.
//
// The resident compiler does not maintain token-range scope_end records. HIR
// declaration scope is carried by compact declaration records and a segment tree
// over those records.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> hir_value_decl_name_present;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 20u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        hir_value_decl_name_present[i] = 0u;

    if (i >= active_token_count())
        return;

    visible_decl[i] = INVALID;
    visible_type[i] = TY_UNKNOWN;
}
