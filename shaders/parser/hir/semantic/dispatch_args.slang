// Build indirect dispatch arguments for dense semantic-HIR passes.
//
// The parser first compactifies semantic HIR nodes with a prefix scan. Passes
// that only need semantic HIR rows can then dispatch over the dense row count
// rather than over every emitted parse-tree production.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemanticDispatch;

StructuredBuffer<uint> hir_semantic_count;
RWStructuredBuffer<uint> hir_semantic_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void write_dispatch_args(uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    hir_semantic_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    hir_semantic_dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    hir_semantic_dispatch_args[2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    write_dispatch_args(min(hir_semantic_count[0u], gHirSemanticDispatch.n));
}
