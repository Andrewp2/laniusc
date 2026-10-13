// Source-job ownership for immutable checked scalar atoms and unary count
// projections. Concrete refs are (1, atom row); parameter refs are (2, exact
// declaration token); projection refs are (3, projection row). The row domains
// are distinct even when physical integers happen to be equal.
import constant_value;
import primitive_types;
import type_checker.constant_parameter_slots;

// Producers inspect admitted prefixes and publish through this same binding.
// A single RW declaration avoids overlapping RO/RW views of one allocation.
public RWStructuredBuffer<uint4> checked_constant_atoms;
public RWStructuredBuffer<uint4> checked_constant_projections;

public bool checked_constant_atom_value(uint row, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    uint count; uint stride;
    checked_constant_atoms.GetDimensions(count, stride);
    if (row >= count) return false;
    uint4 atom = checked_constant_atoms[row];
    if (atom.w != 0u || !constant_value_is_valid(atom.xyz)) return false;
    value = atom.xyz;
    return true;
}

public bool checked_constant_projection(uint row, out uint target_scalar, out uint2 child)
{
    target_scalar = 0u; child = uint2(0u, 0xffffffffu);
    uint count; uint stride;
    checked_constant_projections.GetDimensions(count, stride);
    if (row >= count) return false;
    uint4 projection = checked_constant_projections[row];
    if (!scalar_is_integer(projection.x) || projection.y < 1u || projection.y > 3u ||
        projection.z == 0xffffffffu || projection.w != 0u) return false;
    target_scalar = projection.x;
    child = projection.yz;
    return true;
}

public uint checked_constant_parameter_scalar(uint parameter)
{
    uint count; uint stride;
    type_const_param_scalar_by_token.GetDimensions(count, stride);
    if (parameter >= count) return 0u;
    uint scalar = type_const_param_scalar_by_token[parameter];
    return constant_scalar_is_supported(scalar) ? scalar : 0u;
}

// The replay producer reserves 64 graph-node atoms followed by 32 standalone
// constant arguments at the physical buffer tail. Source/import producers use
// only their separately bounded front regions; reused workspace slack cannot
// collide with replay rows. This function authorizes addressing, not a value.
public bool checked_constant_replay_atom(uint ordinal, out uint row)
{
    row = 0xffffffffu;
    uint count; uint stride;
    checked_constant_atoms.GetDimensions(count, stride);
    if (count < 96u || ordinal >= 96u) return false;
    row = count - 96u + ordinal;
    return true;
}
