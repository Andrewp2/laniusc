// Fold literal leaves outside function bodies and start the constant
// reference rounds (type_checker.semantic.artifact.const_fold).
import type_checker.semantic.artifact.const_fold;
import primitive_types;
import hir_records;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_nearest_fn;
// (rounds started, constants staged in the current round).
RWStructuredBuffer<uint> local_const_fold_state;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_CHAR = 29u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row == 0u)
    {
        // The first round always runs: it also projects constant parameters.
        local_const_fold_state[0u] = 0u;
        local_const_fold_state[1u] = 1u;
    }
    uint hir_count = const_fold_hir_count(gParams.n_hir_nodes);
    if (row >= hir_count) return;
    if (compact_hir_nearest_fn[row] != INVALID) return;
    HirCore core = compact_hir_core[row];
    HirPayload payload = compact_hir_payload[row];
    bool name_reference = core.kind == HIR_NAME_EXPR ||
        core.kind == HIR_PATH_EXPR ||
        (core.kind == HIR_EXPR && payload.a == HIR_EXPR_NAME);
    // An imported constant's path is present from the semantic projection.
    if (name_reference && semantic_value_const_present_by_hir[row] == CONST_PRESENT)
    {
        const_fold_propagate(row, hir_count);
        return;
    }
    if (core.kind != HIR_LITERAL_EXPR ||
        !(payload.a == HIR_EXPR_INT || payload.a == HIR_EXPR_FLOAT ||
          payload.a == HIR_EXPR_CHAR ||
          payload.a == HIR_EXPR_TRUE || payload.a == HIR_EXPR_FALSE))
        return;
    bool f64 = payload.a == HIR_EXPR_FLOAT &&
        (compact_expr_scalar_type[row] >> SCALAR_TYPE_SHIFT) == SCALAR_F64;
    semantic_value_const_by_hir[row] =
        payload.a == HIR_EXPR_TRUE ? uint2(1u, 0u) : payload.a == HIR_EXPR_FALSE ? uint2(0u, 0u) :
        f64 ? uint2(payload.c, payload.d)
            : uint2(payload.b, payload.a == HIR_EXPR_INT ? payload.c : 0u);
    semantic_value_const_present_by_hir[row] = CONST_PRESENT;
    const_fold_propagate(row, hir_count);
}
