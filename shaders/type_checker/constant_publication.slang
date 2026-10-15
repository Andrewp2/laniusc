import primitive_types;
import constant_value;
// Producers alone allocate immutable scalar/projection rows. Matchers never
// publish transient references.
import type_checker.constant_atoms;

// x=first dynamic row, y=exclusive logical limit, z=allocated dynamic rows.
// A dedicated initialization pass owns this header before any producer runs.
public RWStructuredBuffer<uint4> checked_constant_storage_state;

public bool publish_checked_constant_atom_at(uint row, uint3 value, out uint2 reference)
{
    reference = uint2(0u, 0xffffffffu);
    uint count; uint stride;
    checked_constant_atoms.GetDimensions(count, stride);
    if (count < 96u || row >= count - 96u || !constant_value_is_valid(value)) return false;
    checked_constant_atoms[row] = uint4(value, 0u);
    reference = uint2(1u, row);
    return true;
}

public bool reserve_checked_constant_row(out uint row)
{
    row = 0xffffffffu;
    uint4 state = checked_constant_storage_state[0u];
    uint atoms; uint projections; uint stride;
    checked_constant_atoms.GetDimensions(atoms, stride);
    checked_constant_projections.GetDimensions(projections, stride);
    if (atoms < 96u || state.x > state.y || state.y > atoms - 96u || state.y > projections || state.w != 0u)
        return false;
    // Saturate at the declared limit. A failed reservation cannot wrap and
    // overwrite a previously published row, even after repeated failed work.
    uint expected = state.z;
    for (;;)
    {
        if (expected >= state.y - state.x) return false;
        uint previous;
        InterlockedCompareExchange(checked_constant_storage_state[0u].z, expected, expected + 1u, previous);
        if (previous == expected) { row = state.x + expected; return true; }
        expected = previous;
    }
}

public bool publish_checked_constant_projection_at(uint row, uint target, uint2 child, out uint2 reference)
{
    reference = uint2(0u, 0xffffffffu);
    uint count; uint stride;
    checked_constant_projections.GetDimensions(count, stride);
    if (row >= count || !scalar_is_integer(target) || child.x < 1u || child.x > 3u || child.y == 0xffffffffu)
        return false;
    checked_constant_projections[row] = uint4(target, child, 0u);
    reference = uint2(3u, row);
    return true;
}
