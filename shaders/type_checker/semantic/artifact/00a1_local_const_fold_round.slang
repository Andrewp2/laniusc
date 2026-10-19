// Size the next constant reference round (00b, 00b2) from the last one: every
// HIR row while the last round staged a constant, no workgroups once a round
// staged none (nothing new became present, so no later round can either).
// The host records LOCAL_CONST_FOLD_ROUNDS rounds and never reads this back.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
// (rounds started, constants staged in the current round).
RWStructuredBuffer<uint> local_const_fold_state;
RWStructuredBuffer<uint> local_const_fold_dispatch_args;

static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint groups = local_const_fold_state[1u] != 0u ? (hir_count + 255u) / 256u : 0u;
    local_const_fold_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    local_const_fold_dispatch_args[1u] = groups == 0u ? 0u : (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    local_const_fold_dispatch_args[2u] = groups == 0u ? 0u : 1u;
    local_const_fold_state[0u] = local_const_fold_state[0u] + 1u;
    local_const_fold_state[1u] = 0u;
}
