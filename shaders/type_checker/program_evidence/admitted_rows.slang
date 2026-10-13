// Consumers of complete prior row admission, never bootstrap validators.
// Catalog dispatches admit atoms/owners/parameters before callable consumers,
// and nodes/edges/roots before definition graph preflight. Each stage covers
// every row, has a compute-pass barrier, and gates on sticky BUILDING success.
// Batch owners/parameters are frozen catalog rows; new graph rows pass ordered
// suffix admission before environment preflight. Inputs stay immutable.
// These readers retain checked addressing and bounded walks. Row shape alone
// does not prove contextual graph cycles, depth/work, closure or substitution.
// The membership operation below checks lexical visibility for its exact atom.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.constant_atoms;

public static const uint PEV_ADMITTED_DOMAIN_EITHER = 0u;
public static const uint PEV_ADMITTED_DOMAIN_TYPE = 1u;
public static const uint PEV_ADMITTED_DOMAIN_CONSTANT = 2u;

public bool pev_read_admitted_parameter(uint atom, out uint4 parameter)
{
    return pev_read4(1u, atom, 0u, parameter) && parameter.x == 5u &&
        parameter.z <= 1u && parameter.y != PEV_INVALID && parameter.w != PEV_INVALID;
}
public bool pev_admitted_parameter_has_domain(uint atom, bool constant)
{
    uint4 parameter;
    return pev_read_admitted_parameter(atom, parameter) && parameter.z == (constant ? 1u : 0u);
}
public bool pev_admitted_type_reference_shape(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 1u) return pev_scalar_is_valid(reference.y);
    if (reference.x == 2u) return pev_admitted_parameter_has_domain(reference.y, false);
    uint4 low; uint4 high;
    return reference.x == 3u && pev_read8(5u, reference.y, low, high) && low.x >= 1u && low.x <= 4u;
}
public bool pev_admitted_constant_reference_shape(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    uint3 value; uint target; uint2 child;
    return (reference.x == 0x80000001u && pev_constant_atom_value(reference.y, value)) ||
        (reference.x == 0x80000002u && pev_admitted_parameter_has_domain(reference.y, true)) ||
        (reference.x == 0x80000003u && pev_constant_projection(reference.y, target, child));
}

public bool pev_read_admitted_owner(uint owner, out uint4 low, out uint4 high)
{
    low = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); high = low;
    EvidenceTable descriptor;
    // Definitions and lexical owners never come from a batch suffix.
    return pev_descriptor(2u, descriptor) && owner < descriptor.catalog_count &&
        pev_read8(2u, owner, low, high) && high.y <= 64u &&
        (high.y != 0u || high.x == 0u) && pev_row_span(3u, high.x, high.y);
}

// Row admission proved each chain acyclic and each owned parameter exact.
// Membership is still contextual: search the visible lexical chain and match
// the full atom ID, never binding_slot or source_ordinal.
public bool pev_admitted_parameter_visible(uint atom, uint owner)
{
    uint4 parameter;
    if (!pev_read_admitted_parameter(atom, parameter)) return false;
    [loop]
    for (uint depth = 0u; depth < PEV_DEPTH_LIMIT && owner != PEV_INVALID; depth++)
    {
        uint4 low; uint4 high;
        if (!pev_read_admitted_owner(owner, low, high)) return false;
        if (low.x == parameter.y)
        {
            [loop]
            for (uint i = 0u; i < high.y; i++)
            {
                uint4 candidate;
                if (!pev_read4(3u, high.x + i, 0u, candidate) || candidate.x != owner ||
                    candidate.w > 1u || candidate.z >= 32u) return false;
                if (candidate.y == atom) return candidate.w == parameter.z;
            }
            return false;
        }
        owner = low.w;
    }
    return false;
}

// Derive counts from admitted composed scopes without re-proving chain shape,
// ordinal order, distinct slots, or composed-slot order for every consumer.
public EvidenceStatus pev_admitted_owner_parameter_counts(
    uint owner, out uint type_count, out uint constant_count)
{
    type_count = 0u; constant_count = 0u;
    uint original = owner;
    if (owner == PEV_INVALID) return pev_invalid(3u, original, owner);
    [loop]
    for (uint depth = 0u; owner != PEV_INVALID; depth++)
    {
        if (depth == PEV_DEPTH_LIMIT)
            return pev_limit(6u, original, PEV_DEPTH_LIMIT + 1u, PEV_DEPTH_LIMIT);
        uint4 low; uint4 high;
        if (!pev_read_admitted_owner(owner, low, high)) return pev_invalid(3u, original, owner);
        [loop]
        for (uint i = 0u; i < high.y; i++)
        {
            uint4 parameter;
            if (!pev_read4(3u, high.x + i, 0u, parameter) || parameter.x != owner ||
                parameter.w > 1u || parameter.z >= 32u)
                return pev_invalid(4u, owner, high.x + i);
            if (parameter.w == 0u)
            {
                if (type_count == 32u) return pev_limit(19u, original, 33u, 32u);
                type_count++;
            }
            else
            {
                if (constant_count == 32u) return pev_limit(19u, original, 33u, 32u);
                constant_count++;
            }
        }
        owner = low.w;
    }
    return pev_ok();
}

// Shape validation happened once for every Node row, including unused nodes.
// Keep the local bounds required for projections; do not revisit child shapes.
public bool pev_read_admitted_node(uint node, out uint4 low, out uint4 high)
{
    if (!pev_read8(5u, node, low, high) || low.x < 1u || low.x > 5u) return false;
    return low.x != 1u || (low.w <= 32u && (low.w != 0u || low.z == 0u) &&
        pev_row_span(6u, low.z, low.w));
}
public bool pev_read_admitted_child(
    uint4 low, uint4 high, uint slot, out uint2 reference, out uint domain)
{
    reference = uint2(PEV_INVALID, PEV_INVALID); domain = PEV_ADMITTED_DOMAIN_TYPE;
    if (low.x == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_EITHER;
        return low.w <= 32u && slot < low.w && pev_row_span(6u, low.z, low.w) &&
            pev_read2(6u, low.z + slot, 0u, reference);
    }
    if (low.x == 5u && slot == 0u)
    {
        domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.xy;
        return pev_admitted_constant_reference_shape(reference);
    }
    if (low.x == 2u && slot == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_CONSTANT;
        reference = high.zw; // The retained length already has a constant tag.
        return reference.x >= 0x80000001u && reference.x <= 0x80000003u;
    }
    if (low.x >= 2u && low.x <= 4u && slot == 0u)
    {
        reference = high.xy;
        return true;
    }
    return false;
}
