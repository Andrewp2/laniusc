// Retain calls independently of their explicit argument count. Borrowed
// receiver calls and zero-argument generic calls still need an environment.
import hir_records;
import gpu_index;
import checked_semantic_artifact;

struct Params {
    uint n_tokens; uint source_len; uint n_hir_nodes;
    uint n_source_files; uint parser_feature_flags;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
RWStructuredBuffer<uint> retained_callable_flag;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (row >= min(compact_hir_count[0u], gParams.n_hir_nodes)) return;
    uint flag = 0u;
    // The checked call table is initialized only at call-expression rows.
    if (compact_hir_core[row].kind == 19u) {
        CheckedCallArtifact call = semantic_calls_by_hir[row];
        flag = call.callable_kind == 1u ||
            (call.callable_kind == 3u && call.dependency_host_service == 0xffffffffu)
            ? 1u : 0u;
    }
    retained_callable_flag[row] = flag;
}
