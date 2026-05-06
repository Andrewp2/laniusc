struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> enclosing_fn_end;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> scope_end;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
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
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    uint n = active_token_count();
    uint fn_end = enclosing_fn_end[i];
    visible_decl[i] = INVALID;
    visible_type[i] = TY_UNKNOWN;
    scope_end[i] = fn_end == 0u ? n : min(fn_end, n);
}
