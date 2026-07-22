// Reduce projected predicate facts through compact predicate and method rows.
// One lane may own one row from each dense family. No raw production, parent,
// sibling, or raw-to-compact relation crosses this pass boundary.

import fixed.compact_method;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPredicate { uint owner; uint subject; uint bound; uint metadata; };
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
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<PredicateDiagnosticFact> compact_predicate_diagnostic_facts;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint PREDICATE_GENERIC_BOUND = 1u;
static const uint PREDICATE_TRAIT_IMPL = 2u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
static const uint PREDICATE_STATUS_INVALID_ARG = 4u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_BOUND_ARITY_MISMATCH = 13u;
static const uint PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE = 14u;
static const uint PREDICATE_STATUS_INVALID_IMPL_ARG = 15u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND = 18u;
static const uint PREDICATE_STATUS_OVERLAPPING_IMPL = 19u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH = 25u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW = 27u;
static const uint PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG = 28u;
static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_TRAIT_BOUND_UNSATISFIED = 13u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_predicate_count() { return min(gParams.n_hir_nodes, compact_predicate_count[0u]); }
uint active_method_count() { return min(gParams.n_hir_nodes, compact_method_count[0u]); }
bool valid_hir(uint hir) { return hir != INVALID && hir < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

bool method_validation_can_override(uint predicate_status)
{
    return predicate_status == INVALID ||
           predicate_status == PREDICATE_STATUS_OK ||
           predicate_status == PREDICATE_STATUS_MISSING_METHOD ||
           predicate_status == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
           predicate_status == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
           predicate_status == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
           predicate_status == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
           predicate_status == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
           predicate_status == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
           predicate_status == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
           predicate_status == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
           predicate_status == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW;
}

void validate_generic_bound(HirPredicate predicate)
{
    if (!valid_hir(predicate.bound)) return;
    PredicateDiagnosticFact fact = compact_predicate_diagnostic_facts[predicate.bound];
    uint detail = fact.status;
    if (detail == INVALID || detail == PREDICATE_STATUS_OK) return;

    uint token = compact_hir_core[predicate.bound].token_start;
    if (detail == PREDICATE_STATUS_INVALID_SUBJECT && valid_token(predicate.subject))
        token = predicate.subject;
    if ((detail == PREDICATE_STATUS_INVALID_ARG ||
         detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
         detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION) &&
        (valid_token(fact.first_arg_token) || valid_token(fact.second_arg_token)))
    {
        token = valid_token(fact.second_arg_token)
                    ? fact.second_arg_token
                    : fact.first_arg_token;
    }
    if (detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE &&
        token == compact_hir_core[predicate.bound].token_start &&
        valid_token(fact.fallback_arg_token))
        token = fact.fallback_arg_token;

    bool unsupported =
        detail == PREDICATE_STATUS_INVALID_SUBJECT ||
        detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
        detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        detail == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
        detail == PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND ||
        detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
    record_min_token_error(
        status,
        valid_token(token) ? token : 0u,
        unsupported ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_UNKNOWN_TYPE,
        detail);
}

void validate_trait_impl(HirPredicate predicate)
{
    if (!valid_hir(predicate.owner)) return;
    PredicateDiagnosticFact fact = compact_predicate_diagnostic_facts[predicate.owner];
    uint detail = fact.status;
    uint method_detail_token = INVALID;
    if (fact.method_validation_status != INVALID &&
        fact.method_validation_status != PREDICATE_STATUS_OK &&
        method_validation_can_override(detail))
    {
        detail = fact.method_validation_status;
        method_detail_token = fact.method_validation_detail_token;
    }
    if (detail == INVALID || detail == PREDICATE_STATUS_OK) return;

    bool invalid_method =
        detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
        detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        detail == PREDICATE_STATUS_INVALID_ARG ||
        detail == PREDICATE_STATUS_BOUND_NOT_TRAIT ||
        detail == PREDICATE_STATUS_MISSING_METHOD ||
        detail == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
        detail == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
        detail == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
        detail == PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE ||
        detail == PREDICATE_STATUS_INVALID_IMPL_ARG ||
        detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
        detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
        detail == PREDICATE_STATUS_OVERLAPPING_IMPL ||
        detail == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
        detail == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
        detail == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
        detail == PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH ||
        detail == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
        detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW ||
        detail == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
    uint code = detail == PREDICATE_STATUS_INVALID_SUBJECT
                    ? ERR_UNRESOLVED_IDENT
                    : (invalid_method ? ERR_BAD_HIR : ERR_UNKNOWN_TYPE);
    uint token = compact_hir_core[predicate.owner].token_start;
    bool impl_arg_status =
        detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        detail == PREDICATE_STATUS_INVALID_IMPL_ARG ||
        detail == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
    if (impl_arg_status && valid_token(fact.second_arg_token))
        token = fact.second_arg_token;
    else if (valid_token(method_detail_token))
        token = method_detail_token;
    else if ((detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
              detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
              detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
              detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
              detail == PREDICATE_STATUS_INVALID_IMPL_ARG ||
              detail == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG ||
              detail == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
              detail == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
              detail == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH) &&
             valid_token(fact.first_arg_token))
        token = fact.first_arg_token;
    record_min_token_error(status, valid_token(token) ? token : 0u, code, detail);
}

void validate_method(uint row)
{
    CompactMethodCore method = compact_method_cores[row];
    if (!valid_hir(method.node)) return;
    PredicateDiagnosticFact fact = compact_predicate_diagnostic_facts[method.node];
    uint detail = fact.method_validation_status;
    bool validation_error = detail != INVALID && detail != PREDICATE_STATUS_OK;
    if (!validation_error)
    {
        detail = fact.status;
        if (detail == INVALID || detail == PREDICATE_STATUS_OK)
            detail = fact.method_contract_status;
    }
    if (detail == INVALID || detail == PREDICATE_STATUS_OK ||
        detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
        detail == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE)
        return;

    uint token = validation_error && valid_token(fact.method_validation_detail_token)
                     ? fact.method_validation_detail_token
                     : (valid_token(fact.first_arg_token)
                            ? fact.first_arg_token
                            : method.name_token);
    if (!valid_token(token)) token = compact_hir_core[method.node].token_start;
    record_min_token_error(status, valid_token(token) ? token : 0u, ERR_BAD_HIR, detail);
}

void validate_dense_method_fact(uint dense)
{
    PredicateDiagnosticFact fact = compact_predicate_diagnostic_facts[dense];
    uint detail = fact.method_validation_status;
    if (detail == INVALID || detail == PREDICATE_STATUS_OK) return;
    uint token = valid_token(fact.method_validation_detail_token)
                     ? fact.method_validation_detail_token
                     : compact_hir_core[dense].token_start;
    record_min_token_error(status, valid_token(token) ? token : 0u, ERR_BAD_HIR, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < active_hir_count()) validate_dense_method_fact(row);
    if (row < active_predicate_count())
    {
        HirPredicate predicate = compact_predicates[row];
        uint kind = predicate.metadata & 0xffu;
        if (kind == PREDICATE_GENERIC_BOUND) validate_generic_bound(predicate);
        else if (kind == PREDICATE_TRAIT_IMPL) validate_trait_impl(predicate);
    }
    if (row < active_method_count()) validate_method(row);
}
