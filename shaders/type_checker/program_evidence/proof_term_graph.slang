import primitive_types;
import constant_value;
import type_checker.program_evidence.constant_atoms;
// The normalized store has its own compound-node namespace. Leaf atoms remain
// the exact catalog/batch atoms; no parameter slot or page-local token is copied.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.owned_type_constraint_contract;
import type_checker.scoped_type_equality;

// Row decoders read their row once and combine pure field tests without
// short-circuit branches (a failed read leaves an all-INVALID row).
public bool pps_type_reference(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 1u) return pev_scalar_is_valid(reference.y);
    if (reference.x == 2u) return pev_admitted_parameter_has_domain(reference.y, false);
    if (reference.x != 3u) return false;
    uint4 low; uint4 high;
    bool read = pps_read8(PPS_TERM_NODES, reference.y, low, high);
    return read & (low.x >= 1u) & (low.x <= 4u);
}
public bool pps_constant_value(uint row, out uint3 value)
{
    value = uint3(0u, 0u, 0u); uint4 low; uint4 high;
    bool read = pps_read8(PPS_TERM_NODES, row, low, high);
    if (!(read & (low.x == 6u) & all(high == uint4(0u, 0u, 0u, 0u)) &
        constant_value_is_valid(low.yzw))) return false;
    value = low.yzw; return true;
}
public bool pps_constant_projection(uint row, out uint target, out uint2 child)
{
    target = 0u; child = uint2(0u, PEV_INVALID); uint4 low; uint4 high;
    bool read = pps_read8(PPS_TERM_NODES, row, low, high);
    if (!(read & (low.x == 5u) & scalar_is_integer(low.y) & all(low.zw == uint2(0u, 0u)) &
        all(high.zw == uint2(0u, 0u)) & (high.x >= 0x80000001u) & (high.x <= 0x80000003u) &
        (high.y != PEV_INVALID))) return false;
    target = low.y; child = uint2(high.x & 0x7fffffffu, high.y); return true;
}
public bool pps_constant_reference(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    uint3 value; uint target; uint2 child;
    return (reference.x == 0x80000001u && pps_constant_value(reference.y, value)) ||
        (reference.x == 0x80000002u && pev_admitted_parameter_has_domain(reference.y, true)) ||
        (reference.x == 0x80000003u && pps_constant_projection(reference.y, target, child));
}
public uint pps_constant_reference_scalar(uint2 reference)
{
    if (reference.x == 0x80000001u)
    { uint3 value; return pps_constant_value(reference.y, value) ? value.x : 0u; }
    if (reference.x == 0x80000002u) return pev_constant_parameter_scalar(reference.y);
    uint target; uint2 child;
    return reference.x == 0x80000003u && pps_constant_projection(reference.y, target, child) ? target : 0u;
}
public bool pps_read_term_node(uint row, out uint4 low, out uint4 high)
{
    uint4 l; uint4 h;
    bool read = pps_read8(PPS_TERM_NODES, row, l, h);
    low = l; high = h;
    if (!(read & (l.x >= 1u) & (l.x <= 6u))) return false;
    if (l.x != 1u) return true;
    return (l.w <= 32u) & ((l.w != 0u) | (l.z == 0u)) & pps_span(PPS_TERM_EDGES, l.z, l.w);
}
public bool pps_term_child(uint4 low, uint4 high, uint slot,
    out uint2 reference, out uint domain)
{
    reference = uint2(0u, PEV_INVALID); domain = PEV_ADMITTED_DOMAIN_TYPE;
    if (low.x == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_EITHER;
        return low.w <= 32u && slot < low.w &&
            pps_span(PPS_TERM_EDGES, low.z, low.w) && pps_read2(PPS_TERM_EDGES, low.z + slot, 0u, reference);
    }
    if (low.x == 5u && slot == 0u)
    { domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.xy; return pps_constant_reference(reference); }
    if (low.x == 2u && slot == 1u)
    { domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.zw; return pps_constant_reference(reference); }
    if (low.x >= 2u && low.x <= 4u && slot == 0u)
    { reference = high.xy; return pps_type_reference(reference); }
    return false;
}
public struct SolverProofTermGraph : IParameterScopedTypeGraph,
    IConstraintMatchGraph, IProofNormalizationGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return pps_constant_value(row, value); }
    public static uint constant_parameter_scalar(uint parameter)
    { return pev_constant_parameter_scalar(parameter); }
    public static bool constant_projection(uint row, out uint target, out uint2 child)
    { return pps_constant_projection(row, target, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return pev_admitted_parameter_has_domain(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { tag = 0u; payload = PEV_INVALID; return false; }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { kind = 0u; value = PEV_INVALID; return false; }
    public static bool node(uint row, out uint4 low, out uint4 high)
    { return pps_read_term_node(row, low, high); }
    public static bool child(uint4 low, uint4 high, uint slot, out uint2 reference, out uint domain)
    { return pps_term_child(low, high, slot, reference, domain); }
    public static uint metadata(uint instance, uint field)
    {
        uint4 low; uint4 high;
        bool admitted = pps_read_term_node(instance, low, high);
        return select(admitted, pev_node_row_field(low, high, field), PEV_INVALID);
    }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = PEV_INVALID;
        uint4 low; uint4 high; uint2 reference; uint domain;
        if (!pps_read_term_node(instance, low, high) || low.x != 1u ||
            !pps_term_child(low, high, slot, reference, domain)) return false;
        tag = reference.x; payload = reference.y; return true;
    }
}
public struct SolverProofTermSink : IProofNormalizationSink
{
    public static bool begin_node(uint row, uint4 low, uint4 high)
    { return pps_write8(PPS_TERM_NODES, row, low, high); }
    public static bool set_child(uint row, uint slot, uint2 reference)
    {
        // This row is reserved but deliberately not yet readable through the
        // admitted graph adapter. Only its unique emitter may fill children.
        uint address;
        if (!pps_address(PPS_TERM_NODES, row, 0u, 8u, true, address)) return false;
        uint kind = program_evidence_proof_store[address];
        if (kind == 1u)
        {
            uint first = program_evidence_proof_store[address + 2u];
            uint count = program_evidence_proof_store[address + 3u];
            if (count > 32u || slot >= count || first > PEV_INVALID - slot) return false;
            return pps_write2(PPS_TERM_EDGES, first + slot, 0u, reference);
        }
        if (kind < 2u || kind > 5u || slot > (kind == 2u ? 1u : 0u)) return false;
        // Physical full-row proof above includes these two scalar writes.
        uint field = slot == 0u ? 4u : 6u;
        program_evidence_proof_store[address + field] = reference.x;
        program_evidence_proof_store[address + field + 1u] = reference.y;
        return true;
    }
}
public struct SolverProofBindings : IProofNormalizationBindings
{
    public static bool replacement(uint substitution, uint parameter, bool constant, out uint2 reference)
    {
        reference = uint2(0u, PEV_INVALID);
        uint4 row;
        if (!pps_read4(PPS_SUBSTITUTIONS, substitution, 0u, row) || row.z > 64u ||
            !pps_span(PPS_BINDINGS, row.y, row.z) ||
            !pev_admitted_parameter_has_domain(parameter, constant)) return false;
        // Binding rows are sorted by exact atom and admitted complete/unique.
        uint lo = 0u; uint hi = row.z;
        [loop]
        for (uint step = 0u; step < 7u && lo < hi; step++)
        {
            uint middle = lo + (hi - lo) / 2u; uint4 binding;
            if (!pps_read4(PPS_BINDINGS, row.y + middle, 0u, binding) || binding.x != substitution) return false;
            if (binding.y == parameter)
            {
                reference = binding.zw;
                return constant ? pps_constant_reference(reference) : pps_type_reference(reference);
            }
            if (binding.y < parameter) lo = middle + 1u; else hi = middle;
        }
        return false;
    }
}
