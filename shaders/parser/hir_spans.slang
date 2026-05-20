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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_path_leaf_node;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_ll1 != 0u ? min(gHir.n, ll1_status[5u]) : gHir.n;
}

uint clamped_end_after_token(uint token_pos)
{
    uint n_tokens = token_count[0];
    return token_pos >= n_tokens ? n_tokens : token_pos + 1u;
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

    if (hir_kind[i] == HIR_PATH_EXPR)
    {
        uint leaf = hir_type_path_leaf_node[i];
        uint leaf_candidate = leaf < n ? hir_token_pos[leaf] : INVALID;
        uint leaf_pos = leaf_candidate == INVALID ? start : leaf_candidate;
        hir_token_end[i] = clamped_end_after_token(leaf_pos);
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

    hir_token_end[i] = clamped_end_after_token(max_pos);
}
