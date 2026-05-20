// Build indirect dispatch arguments for LLP parser passes from GPU-resident
// lexer token_count. This avoids host readback while keeping pair-local passes
// scheduled over the active token-pair range instead of source-byte capacity.

struct Params
{
    uint n_tokens;
    uint n_kinds;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> active_pair_thread_dispatch_args;
RWStructuredBuffer<uint> active_pair_group_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_pair_count()
{
    if (gParams.n_tokens < 2u)
        return 0u;
    uint active_tokens = min(gParams.n_tokens, token_count[0u] + 2u);
    return active_tokens > 0u ? active_tokens - 1u : 0u;
}

void write_args(RWStructuredBuffer<uint> args, uint groups)
{
    uint safe_groups = max(1u, groups);
    args[0u] = min(safe_groups, MAX_GROUPS_X);
    args[1u] = max(1u, (safe_groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint pairs = active_pair_count();
    write_args(active_pair_thread_dispatch_args, (pairs + WG_SIZE - 1u) / WG_SIZE);
    write_args(active_pair_group_dispatch_args, pairs);
}
