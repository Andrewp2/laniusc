// Initialize the source-owned constant arena once per compilation job. Fixed
// source/array/dependency regions precede the bounded producer arena. Replay
// atoms are reserved at the physical tail by their sole replay writer.
import type_checker.constant_storage_plan;
import constant_value;
import gpu_index;
#include "body_graph_layout.slang"
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> type_const_param_scalar_by_token_out;
RWStructuredBuffer<uint4> checked_constant_atoms;
RWStructuredBuffer<uint4> checked_constant_projections;
RWStructuredBuffer<uint4> checked_constant_storage_state;
RWStructuredBuffer<uint2> dependency_constant_ref_by_type_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint thread = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint step = max(gParams.n_tokens, 1u);
    if (thread >= step) return;
    uint atoms; uint projections; uint maps; uint scalars; uint stride;
    type_const_param_scalar_by_token_out.GetDimensions(scalars, stride);
    checked_constant_atoms.GetDimensions(atoms, stride);
    checked_constant_projections.GetDimensions(projections, stride);
    dependency_constant_ref_by_type_out.GetDimensions(maps, stride);
    uint4 plan = uint4(gConstantStoragePlan.imported_base, gConstantStoragePlan.dynamic_base,
        gConstantStoragePlan.dynamic_limit, gConstantStoragePlan.total_rows);
    bool valid = plan.x <= plan.y && plan.y <= plan.z &&
        plan.z <= plan.w && plan.w - plan.z == BODY_ATOM_RESERVE_ROWS &&
        plan.w <= atoms && plan.w <= projections;
    if (thread == 0u)
        checked_constant_storage_state[0u] = valid ? uint4(plan.y, plan.z, 0u, 0u) :
            uint4(0u, 0u, 0u, 1u);
    // This pass has no readers of atom/projection contents. Strided ownership
    // clears reused workspace slack and cannot race a source/replay producer.
    for (uint row = thread; row < scalars;)
    {
        type_const_param_scalar_by_token_out[row] = 0u;
        if (scalars - row <= step) break;
        row += step;
    }
    for (uint row = thread; row < atoms;)
    {
        checked_constant_atoms[row] = uint4(0u, 0u, 0u, 0u);
        if (atoms - row <= step) break;
        row += step;
    }
    for (uint row = thread; row < projections;)
    {
        checked_constant_projections[row] = uint4(0u, 0u, 0u, 0u);
        if (projections - row <= step) break;
        row += step;
    }
    for (uint row = thread; row < maps;)
    {
        dependency_constant_ref_by_type_out[row] = uint2(0u, 0xffffffffu);
        if (maps - row <= step) break;
        row += step;
    }
}
