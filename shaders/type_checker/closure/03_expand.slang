// One instance-closure round: one lane per frontier instance (F, E). Each
// edge of F (a call to a generic local body inside F) gets its call
// environment substituted under E, and the callee's instance is inserted
// one level deeper. Edges whose environment stays open or has a hole under
// E are counted and left to the replays. An edge whose constant projection
// does not fit under E is the instance's failed fit: a type mismatch at the
// argument that claims the slot, with the scalar it does not fit.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_generic_claim_pattern_mask;
StructuredBuffer<uint> call_const_claim_pattern_mask;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
// A type mismatch whose detail is a count fit (calls/03a1_emit_generic_claims,
// gpu_compiler/helpers.rs ASSIGN_MISMATCH_COUNT_FIT): the low bits are the
// scalar the value does not fit.
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ASSIGN_MISMATCH_COUNT_FIT = 0x40000000u;

#include "closure_calls.slang"

// The first argument of `call` whose parameter pattern names the slot, or
// the call's own token. A call's arguments claim each slot they name
// (03a1), so this is the argument whose length the slot was inferred from
// or checked against.
uint fit_argument_token(uint call, uint slot, bool constant)
{
    uint rows; uint stride;
    call_arg_row_node.GetDimensions(rows, stride);
    uint start = call_arg_row_start[call];
    uint count = start < rows ? min(call_arg_row_count[call], rows - start) : 0u;
    for (uint row = start; row < start + count; row++)
    {
        uint mask = constant ? call_const_claim_pattern_mask[row] : call_generic_claim_pattern_mask[row];
        uint node = call_arg_row_node[row];
        if ((mask & (1u << slot)) != 0u && valid_node(node)) return compact_hir_core[node].token_start;
    }
    return compact_hir_core[call].token_start;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = instance_closure_counts[IC_COUNT_START] + dtid.x + dtid.y * 16776960u;
    if (index >= instance_closure_counts[IC_COUNT_END]) return;
    uint4 instance = instance_closure_instances[2u * index];
    if (!valid_node(instance.y)) return;
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint link = ic_first_edge(instance.y);
    for (uint step = 0u; step < hir_count() && link != 0u; step++)
    {
        uint call = link - 1u;
        link = ic_next_edge(call);
        uint token; uint callee; uint2 masks;
        if (!valid_node(call) || !closure_call(call, token, callee, masks)) continue;
        uint3 failed_fit;
        uint key = closure_instance_env_of(ct_call_env(token).x, callee, masks, instance.x,
            subst_spare, env_spare, failed_fit);
        if (key == CT_FIT_FAILED)
            record_min_token_error(status, fit_argument_token(call, failed_fit.x, failed_fit.y != 0u),
                ERR_ASSIGN_MISMATCH, ASSIGN_MISMATCH_COUNT_FIT | failed_fit.z);
        if (!ct_is_record(key))
        {
            ic_count(IC_COUNT_SKIPPED);
            continue;
        }
        ic_insert(key, callee, instance.z + 1u, call);
    }
}
