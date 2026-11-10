// Withhold the bodies whose in-place instantiation failed
// (inplace_read.slang): one lane per call expression row, after the call
// results. Lowering publishes a generic function's body only when none of
// its calls has a symbolic environment, so one such call keeps the function
// a template, and the replays instantiate it as they do every other.
import hir_records;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> instance_inplace_owner;
StructuredBuffer<uint> instance_inplace_counts;
RWStructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;

static const uint INPLACE_FAILED = 0x40000000u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (instance_inplace_counts[0u] == 0u) return;
    if (row >= min(gParams.n_hir_nodes, compact_hir_count[0u]) || compact_hir_core[row].kind != 19u) return;
    uint owner = compact_hir_nearest_fn[row];
    uint rows; uint stride;
    instance_inplace_owner.GetDimensions(rows, stride);
    if (owner >= rows || (instance_inplace_owner[owner] & INPLACE_FAILED) == 0u) return;
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    if (call.symbolic_type_environment != 0u) return;
    call.symbolic_type_environment = 1u;
    semantic_calls_by_hir[row] = call;
}
