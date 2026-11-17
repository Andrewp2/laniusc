// One instance-closure round over the frontier instances (F, E), with
// IC_LANES_PER_INSTANCE lanes each. The instance's first lane expands its
// call edges and the first lane of its second wave its bound-member edges,
// so the two walks run side by side in one dispatch.
//
// Call edges: each edge of F (a call to a generic local body inside F) gets
// its call environment substituted under E, and the callee's instance is
// inserted one level deeper. Edges whose environment stays open or has a
// hole under E are counted and left to the replays. An edge whose constant
// projection does not fit under E is the instance's failed fit: a type
// mismatch at the argument that claims the slot, with the scalar it does
// not fit.
//
// Bound-member edges (D3; 01_mark links them): each bound-member call of F,
// `value.member(...)` with `value` of F's type parameter P, routes under E
// as methods/09 routes it in a replay (bound_route.slang). A nongeneric
// implementation's method is concrete and needs no instance. A generic one's
// method is inserted one level deeper with the environment its pattern binds
// from R and its routed target (instance_closure_targets).
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;
import type_checker.methods.lookup;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> fn_start_token_by_decl_token;
// Functions that are not instantiated in place (04b_select_inplace).
RWStructuredBuffer<uint> instance_inplace_owner;

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

static const uint INPLACE_BLOCKED = 0x80000000u;

void inplace_block(uint row)
{
    uint rows; uint stride;
    instance_inplace_owner.GetDimensions(rows, stride);
    uint ignored;
    if (row < rows) InterlockedOr(instance_inplace_owner[row], INPLACE_BLOCKED, ignored);
}

#include "closure_calls.slang"
#include "bound_route.slang"

// Route bound call `call` (method token `token`) of frontier instance
// `instance` and insert the generic implementation method it reaches.
void route_bound_edge(uint call, uint token, uint4 instance, inout CtSpare subst_spare,
    inout CtSpare env_spare)
{
    uint env;
    uint selected = route_bound_call(token, instance.x, subst_spare, env_spare, env);
    if (selected == INVALID)
    {
        ic_count(IC_COUNT_SKIPPED);
        inplace_block(instance.y);
        return;
    }
    // A nongeneric implementation's method is concrete.
    if (!ct_is_record(env)) return;
    // A generic implementation's method is an instance the replays patch
    // into the caller's body.
    inplace_block(instance.y);
    HirMethodCore core = compact_method_cores[selected];
    uint candidate = core.name_token;
    uint member = fn_hir_by_decl_token[candidate];
    // The routed callee as methods/09 publishes it and host retention reads
    // it: its function start token (backend_call_fn_index), and a public
    // method's HIR or a private one's start token as its native symbol;
    // then its type parameter count, and its constant parameter count
    // shifted by 16.
    uint start = fn_start_token_by_decl_token[candidate];
    start = valid_token(start) ? start : candidate;
    bool public_method = (compact_method_signatures[selected].metadata & 0xffffu) == 1u;
    uint types = ct_type_slots(env);
    uint4 target = uint4(start, public_method ? (0x80000000u | core.node) : (0x40000000u | start),
        0x80000000u | core.node, types | ((ct_arity(env) - types) << 16u));
    ic_insert_target(env, member, instance.z + 1u, call, target);
}

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

// The call edges of frontier instance `instance`.
void expand_call_edges(uint4 instance)
{
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

// The bound-member edges of frontier instance `instance`.
void expand_bound_edges(uint4 instance)
{
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint link = ic_first_edge(instance.y);
    for (uint step = 0u; step < hir_count() && link != 0u; step++)
    {
        uint call = link - 1u;
        link = ic_next_edge(call);
        uint token;
        if (valid_node(call) && closure_bound_call(call, token))
            route_bound_edge(call, token, instance, subst_spare, env_spare);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint index = instance_closure_counts[IC_COUNT_START] + lane / IC_LANES_PER_INSTANCE;
    uint part = lane % IC_LANES_PER_INSTANCE;
    if ((part != 0u && part != IC_BOUND_LANE) || index >= instance_closure_counts[IC_COUNT_END]) return;
    uint4 instance = instance_closure_instances[2u * index];
    if (!valid_node(instance.y)) return;
    if (part == 0u) expand_call_edges(instance);
    else expand_bound_edges(instance);
}
