// Legacy visible-name scatter fallback.
//
// The supported HIR path resolves names in type_check_visible_04_hir_names from
// compact declaration records, sorted keys, and scope-end tree aggregates. This
// shader intentionally performs no token backscan. Token-only callers fail
// closed later in type_check_scope.slang instead of manufacturing visibility by
// source-shaped scans.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    uint token_i = linear_thread_id(dtid);
    if (gParams.n_hir_nodes == 0u && token_i < active_token_count())
        visible_decl[token_i] = INVALID;
}
