// Scatter the winning predicate validation row into one fixed-width fact keyed
// by dense compact HIR. A preceding atomic claim pass makes this deterministic
// even when grammar forwarding rows share the same semantic dense node.

import gpu_index;
import hir_records;

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

struct TokenIn { uint kind; uint start; uint len; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_validation_first_error_row;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_validation_detail_token;
RWStructuredBuffer<PredicateDiagnosticFact> compact_predicate_diagnostic_facts;

static const uint INVALID = 0xffffffffu;
static const uint TK_LT = 12u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint PARSER_FEATURE_TYPE_ARGS = 0x00000001u;
static const uint PARSER_FEATURE_PREDICATES = 0x00000020u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_compact_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint fallback_bound_arg_token(uint dense)
{
    uint bound_token = dense < active_compact_count()
        ? compact_hir_core[dense].token_start
        : INVALID;
    if (!valid_token(bound_token)) return INVALID;

    [unroll]
    for (uint offset = 1u; offset <= 3u; ++offset)
    {
        uint candidate = bound_token + offset;
        if (candidate < bound_token || !valid_token(candidate)) continue;
        uint kind = token_words[candidate].kind;
        if (kind == TK_BOUND_TYPE_IDENT) return candidate;
        if (offset <= 2u && (kind == TK_LT || kind == TK_GENERIC_PARAM_LT))
        {
            uint arg = candidate + 1u;
            return arg >= candidate && valid_token(arg) ? arg : INVALID;
        }
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint compact_count = active_compact_count();
    bool has_predicate_storage =
        (gParams.parser_feature_flags &
         (PARSER_FEATURE_TYPE_ARGS | PARSER_FEATURE_PREDICATES)) != 0u;
    if (has_predicate_storage && row < compact_count)
    {
        uint dense = row;
        if (dense < compact_count &&
            compact_predicate_diagnostic_facts[dense].winner_raw == dense)
        {
            compact_predicate_diagnostic_facts[dense].status = predicate_status[dense];
            compact_predicate_diagnostic_facts[dense].first_arg_token =
                predicate_bound_first_arg_token[dense];
            compact_predicate_diagnostic_facts[dense].second_arg_token =
                predicate_bound_second_arg_token[dense];
            compact_predicate_diagnostic_facts[dense].fallback_arg_token =
                fallback_bound_arg_token(dense);
        }
    }

    if (row >= compact_count) return;
    compact_predicate_diagnostic_facts[row].method_contract_status =
        predicate_method_contract_status[row];
    uint validation_status = predicate_method_validation_status[row];
    uint validation_detail = predicate_method_validation_detail_token[row];
    uint error_row = predicate_method_validation_first_error_row[row];
    if ((validation_status == INVALID || validation_status == 0u) &&
        error_row < compact_count)
    {
        validation_status = predicate_method_validation_status[error_row];
        validation_detail = predicate_method_validation_detail_token[error_row];
    }
    compact_predicate_diagnostic_facts[row].method_validation_status = validation_status;
    compact_predicate_diagnostic_facts[row].method_validation_detail_token = validation_detail;
}
