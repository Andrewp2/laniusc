// Lists, once per job before the inference rounds, the locations that can
// hold a root of the call field closure (04_expand_call_roots): each call
// row with a call token (its result) and each argument row's context root
// (its expected type). Both depend only on the HIR and the argument rows, which
// are complete before the rounds. An entry is (HIR row, token | family << 31,
// the instance row last pushed from it, 0). One lane per HIR row and per
// argument row; call_root_count and call_root_args were cleared before.
import shared.syntax.hir_records;
import type_checker.argument_context;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
RWStructuredBuffer<uint4> call_root_list;
RWStructuredBuffer<uint> call_root_count;
RWStructuredBuffer<uint> call_root_args;

static const uint INVALID = 0xffffffffu;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

#include "call_root_token.slang"

void list_root(uint node, uint token, uint family)
{
    if (node >= hir_count() || token >= gParams.n_tokens) return;
    uint slot; uint capacity; uint stride;
    InterlockedAdd(call_root_count[0u], 1u, slot);
    call_root_list.GetDimensions(capacity, stride);
    if (slot >= capacity) return; // Two entries per HIR row at most.
    call_root_list[slot] = uint4(node, token | (family << 31u), INVALID, 0u);
    uint groups = slot / 256u + 1u;
    InterlockedMax(call_root_args[0u], min(groups, 65535u));
    InterlockedMax(call_root_args[1u], (groups + 65534u) / 65535u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    // At least one workgroup: 04 also re-queues deferred imported IDs.
    if (lane == 0u)
    {
        InterlockedMax(call_root_args[0u], 1u);
        InterlockedMax(call_root_args[1u], 1u);
        call_root_args[2u] = 1u;
    }
    if (lane >= hir_count()) return;
    list_root(lane, call_token(lane), 0u);
    if (lane < min(call_arg_row_count_out[0u], gParams.n_hir_nodes))
        list_root(argument_context_root(call_arg_row_node[lane], hir_count(),
            compact_hir_core, compact_hir_payload), call_token(call_arg_row_call_node[lane]), 1u);
}
