// One constant reference round, publish phase: the constant uses staged by
// 00b become present, and outside function bodies their parents fold
// (type_checker.semantic.artifact.const_fold).
import type_checker.semantic.artifact.const_fold;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_nearest_fn;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = const_fold_hir_count(gParams.n_hir_nodes);
    if (row >= hir_count || semantic_value_const_present_by_hir[row] != CONST_STAGED) return;
    semantic_value_const_present_by_hir[row] = CONST_PRESENT;
    if (compact_hir_nearest_fn[row] == INVALID) const_fold_propagate(row, hir_count);
}
