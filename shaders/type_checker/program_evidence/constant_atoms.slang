import primitive_types;
// Immutable catalog/batch atoms. Row addresses are storage references only;
// equality and hashing read the complete typed tuple.
import type_checker.program_evidence.abi;
import constant_value;

// Row decoders read their row once and combine pure field tests without
// short-circuit branches (a failed read leaves an all-INVALID row).
public bool pev_constant_atom_value(uint atom, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    uint4 low; uint4 high;
    bool read = pev_read8(1u, atom, low, high);
    if (!(read & (low.x == 12u) & all(high == uint4(0u, 0u, 0u, 0u)) &
        constant_value_is_valid(low.yzw))) return false;
    value = low.yzw;
    return true;
}

public uint pev_constant_parameter_scalar(uint atom)
{
    uint4 low; uint4 high;
    bool read = pev_read8(1u, atom, low, high);
    bool valid = read & (low.x == 5u) & (low.z == 1u) & all(high.yzw == uint3(0u, 0u, 0u)) &
        constant_scalar_is_supported(high.x);
    return select(valid, high.x, 0u);
}

public bool pev_constant_projection(uint node, out uint target_scalar, out uint2 child)
{
    target_scalar = 0u; child = uint2(0u, PEV_INVALID);
    uint4 low; uint4 high;
    bool read = pev_read8(5u, node, low, high);
    if (!(read & (low.x == 5u) & scalar_is_integer(low.y) & all(low.zw == uint2(0u, 0u)) &
        all(high.zw == uint2(0u, 0u)) & (high.x >= 0x80000001u) & (high.x <= 0x80000003u) &
        (high.y != PEV_INVALID))) return false;
    target_scalar = low.y;
    child = uint2(high.x & 0x7fffffffu, high.y);
    return true;
}

// A binding's domain includes the exact declared scalar, independently of the
// constant graph's storage or count projection obligations.
public uint pev_constant_reference_scalar(uint2 reference)
{
    if (reference.x == 0x80000001u)
    { uint3 value; return pev_constant_atom_value(reference.y, value) ? value.x : 0u; }
    if (reference.x == 0x80000002u) return pev_constant_parameter_scalar(reference.y);
    uint target; uint2 child;
    return reference.x == 0x80000003u && pev_constant_projection(reference.y, target, child) ? target : 0u;
}
