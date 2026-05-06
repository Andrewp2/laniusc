// Compute token spans for HIR-facing parse nodes.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHir;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_ll1 != 0u ? min(gHir.n, ll1_status[5u]) : gHir.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint start = hir_token_pos[i];
    if (start == INVALID)
    {
        hir_token_end[i] = INVALID;
        return;
    }

    uint end_node = min(subtree_end[i], n);
    uint max_pos = start;
    if (end_node > i + 1u)
    {
        uint last_pos = hir_token_pos[end_node - 1u];
        if (last_pos != INVALID)
            max_pos = last_pos;
    }

    uint n_tokens = token_count[0];
    hir_token_end[i] = max_pos >= n_tokens ? n_tokens : max_pos + 1u;
}
