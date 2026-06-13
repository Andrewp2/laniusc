// Legacy per-token block scope fallback.
//
// HIR declaration scope ends now come from parser-owned statement records and
// are compacted into hir_visible_decl_scope_end before the visible-name lookup
// tree is built. This pass remains only as a compatibility stage in the legacy
// standalone schedule; it does not publish token-range scope facts.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> scope_end;

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
        scope_end[token_i] = scope_end[token_i];
}
