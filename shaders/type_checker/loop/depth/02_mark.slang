import atomics;

struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;

RWStructuredBuffer<int> if_delta;

static const uint INVALID = 0xffffffffu;
static const uint HIR_IF_STMT = 10u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u
        ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    HirCore core = compact_hir_core[i];
    if (core.kind != HIR_IF_STMT)
        return;

    uint start = core.token_start;
    if (start == INVALID || start >= gParams.n_tokens)
        return;

    uint end = core.token_end;
    if (end == INVALID || end <= start)
        return;

    uint bounded_end = min(end, gParams.n_tokens);
    atomic_i32_add(if_delta, start, 1);
    atomic_i32_add(if_delta, bounded_end, -1);
}
