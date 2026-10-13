import type_checker.constant_atoms_identity;
import type_checker.calls.contextual_call_environment;
// Observation only. The harness runs the production claim index, validation,
// and explicit publication stages before this reader. Expected values live in
// Rust, independently of this shader's reported observations.
import type_checker.calls.checked_constant_environment;

StructuredBuffer<uint4> queries;
StructuredBuffer<uint> call_const_claim_selected;
StructuredBuffer<uint> status;
RWStructuredBuffer<uint4> results;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint4 query = queries[0u];
    uint kind; uint payload; uint mode; uint selected;
    bool binding = checked_call_environment_constant_binding(query.x, query.y,
        kind, payload, mode, selected);
    uint context_kind; uint context_payload; uint context_mode;
    bool context = checked_context_environment_constant_binding(query.x, query.y,
        context_kind, context_payload, context_mode);
    uint3 value;
    bool executable = checked_source_constant_value(query.z, query.w,
        checked_source_constant_parameter_capacity(), value);
    uint capacity; uint stride;
    call_const_claim_selected.GetDimensions(capacity, stride);
    uint count = min(call_const_claim_count_out[0u], capacity);
    uint selected_count = 0u;
    for (uint row = 0u; row < count; row++) selected_count += call_const_claim_selected[row];
    results[0u] = uint4(binding ? 1u : 0u, kind, payload, mode);
    results[1u] = uint4(selected, context ? 1u : 0u, context_kind, context_payload);
    results[2u] = uint4(context_mode, executable ? 1u : 0u, value.x, value.y);
    results[3u] = uint4(value.z, status[0u], selected_count, 0u);
}
