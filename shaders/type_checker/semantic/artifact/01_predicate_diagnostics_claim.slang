// Arbitrate forwarding raw rows that map to the same compact HIR node. Only
// rows carrying an actual predicate or method diagnostic participate.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};
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
StructuredBuffer<uint> predicate_status;
RWStructuredBuffer<PredicateDiagnosticFact> compact_predicate_diagnostic_facts;
static const uint INVALID = 0xffffffffu;
static const uint PARSER_FEATURE_TYPE_ARGS = 0x00000001u;
static const uint PARSER_FEATURE_PREDICATES = 0x00000020u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_compact_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}
bool error_status(uint value) { return value != INVALID && value != 0u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (dense >= active_compact_count() ||
        (gParams.parser_feature_flags &
         (PARSER_FEATURE_TYPE_ARGS | PARSER_FEATURE_PREDICATES)) == 0u)
        return;

    bool carries_error = error_status(predicate_status[dense]);
    if (!carries_error) return;

    uint ignored;
    InterlockedMin(compact_predicate_diagnostic_facts[dense].winner_raw, dense, ignored);
}
