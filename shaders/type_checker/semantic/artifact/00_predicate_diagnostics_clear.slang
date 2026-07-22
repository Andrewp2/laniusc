// Initialize one dense predicate diagnostic fact per compact HIR row.

import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct PredicateDiagnosticFact
{
    uint status;
    uint first_arg_token;
    uint second_arg_token;
    uint fallback_arg_token;
    uint method_contract_status;
    uint method_validation_status;
    uint method_validation_detail_token;
    uint winner_raw;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
RWStructuredBuffer<PredicateDiagnosticFact> compact_predicate_diagnostic_facts;
static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (dense >= min(gParams.n_hir_nodes, compact_hir_count[0u])) return;
    PredicateDiagnosticFact fact;
    fact.status = INVALID;
    fact.first_arg_token = INVALID;
    fact.second_arg_token = INVALID;
    fact.fallback_arg_token = INVALID;
    fact.method_contract_status = INVALID;
    fact.method_validation_status = INVALID;
    fact.method_validation_detail_token = INVALID;
    fact.winner_raw = INVALID;
    compact_predicate_diagnostic_facts[dense] = fact;
}
