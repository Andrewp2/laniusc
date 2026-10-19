// Roots of the dependency closure (D1b; summary.slang): one lane per call
// expression row whose callee is a dependency function with a summary row.
// A call whose value environment is complete and closed is an instance of
// that function at depth 1: its environment tagged with SUMMARY_TAG | the
// function's summary row. 03b expands it through the function's edges.
// 01_mark keeps the job's local calls; a dependency callee is never one.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;
import type_checker.closure.summary;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;

static const uint INVALID = 0xffffffffu;

#include "closure_calls.slang"

// The tagged root environment of the call at `token` into summary function
// `f`, or CT_NONE when the call environment is partial, open or of another
// shape than the function's composed slots.
uint dependency_root_env(uint token, uint f, inout CtSpare env_spare)
{
    uint environment = ct_call_env(token).x;
    if (!ct_is_record(environment) || ct_kind(environment) != CT_KIND_ENV || !ct_closed(environment))
        return CT_NONE;
    uint3 words = ct_words(environment);
    uint4 tail = summary_fn_tail(f);
    uint2 counts = required_callable_generic_counts(token);
    if (words.y != tail.y || words.z != tail.z ||
        words.y != low_bits(counts.x) || words.z != low_bits(counts.y)) return CT_NONE;
    uint arity = ct_arity(environment);
    CtKey key = ct_key_begin(CT_KIND_ENV, arity, ct_type_slots(environment),
        uint3(SUMMARY_TAG | f, words.y, words.z));
    if (!ct_spare_reserve(env_spare, key)) return CT_UNKNOWN;
    for (uint index = 0u; index < arity; index++) ct_key_arg(key, index, ct_arg(environment, index));
    if (!key.ok) return CT_UNKNOWN;
    return ct_spare_publish(key, uint2(0xffffffffu, 0u), true, env_spare);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count() || compact_hir_core[call].kind != HIR_CALL_EXPR) return;
    uint token = call_token(call);
    if (!valid_token(token) || call_dependency_library_id[token] == INVALID) return;
    uint f = summary_find_fn(uint3(call_dependency_library_id[token],
        call_dependency_unit_id[token], call_dependency_local_index[token]));
    // A function without edges (or incomplete) reaches nothing deeper.
    uint2 edges = summary_fn_edges(f);
    if (edges.y <= edges.x) return;
    CtSpare env_spare = ct_spare_none();
    uint key = dependency_root_env(token, f, env_spare);
    if (ct_is_record(key)) ic_insert(key, SUMMARY_TAG | f, 1u, call);
}
