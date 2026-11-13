// Count the calls of an original job that the whole-program trait solver
// must still see (word 2 of `solver_demand`): one lane per call expression
// row, after the in-place guard.
//
// A call needs nothing from the solver when its target's body is complete in
// this job's object or in its provider's:
// - a local callable with no type or constant parameter of its own or of an
//   enclosing implementation (a required trait member is one: its calls are
//   routed while the calling body is bound);
// - a local generic function instantiated in place (inplace_read.slang);
// - a dependency callable without generic requirements, or a host service.
// Every other callable call counts: a local generic body that waits for a
// replay, and a dependency generic, which only a replay instantiates.
//
// With words 0 and 1 (predicates/02_obligations.slang) the three counts are
// zero exactly when the unit's own job has decided every bound and emitted
// every body the unit needs; the host then links the unit without reading
// its call and contract facts back.
import hir_records;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> call_dependency_generic_requirements;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
RWStructuredBuffer<uint> solver_demand;
#include "inplace_read.slang"

static const uint INVALID = 0xffffffffu;
static const uint HIR_FILE = 1u;
static const uint HIR_ITEM = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint CALLABLE_FUNCTION = 1u;
static const uint CALLABLE_DEPENDENCY = 3u;
static const uint SOLVER_DEMAND_CALLS = 2u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

// The callee token of call row `call` (semantic/artifact/00_calls.slang).
uint callee_token(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (token >= gParams.n_tokens) token = core.token_start;
    return token < gParams.n_tokens ? token : INVALID;
}

// Whether function row `function` has a parameter of its own or inherits
// one from an enclosing scope. A trait's parameters are not its required
// members' own: the trait item ends the walk.
bool generic_callable(uint function)
{
    if (compact_generic_param_ranges[function].count != 0u) return true;
    uint count = hir_count();
    uint node = compact_hir_core[function].parent;
    for (uint depth = 0u; depth < count && node < count; depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_FILE) return false;
        if (kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT) return false;
        if (compact_generic_param_ranges[node].count != 0u) return true;
        uint parent = compact_hir_core[node].parent;
        if (parent >= node) break;
        node = parent;
    }
    // No file row above the function: leave it to the solver.
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= hir_count() || compact_hir_core[row].kind != HIR_CALL_EXPR) return;
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    bool demand = false;
    if (call.callable_kind == CALLABLE_DEPENDENCY)
    {
        uint token = callee_token(row);
        demand = call.dependency_host_service == INVALID &&
            (token == INVALID ||
             (call_dependency_generic_requirements[token] & 0x7fffffffu) != 0u);
    }
    else if (call.callable_kind == CALLABLE_FUNCTION)
    {
        uint token = callee_token(row);
        uint target = token != INVALID ? call_fn_index[token] : INVALID;
        uint function = target < gParams.n_tokens ? fn_hir_by_decl_token[target] : INVALID;
        if (function >= hir_count() || compact_hir_core[function].kind != HIR_FN)
            demand = true;
        else
            demand = generic_callable(function) && inplace_instance(function) == INPLACE_NONE;
    }
    if (demand)
    {
        uint ignored;
        InterlockedAdd(solver_demand[SOLVER_DEMAND_CALLS], 1u, ignored);
    }
}
