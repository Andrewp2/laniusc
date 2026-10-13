import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.constant_atoms;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.native_layout.recipe_abi;
import type_checker.program_evidence.native_layout.work_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.scoped_type_equality;
import constant_value;
import primitive_types;

public bool plm_node(uint row, bool pending, out uint4 low, out uint4 high)
{
    return plm_read4(0u, row, 0u, pending, low) && plm_read4(0u, row, 4u, pending, high) &&
        low.x >= 1u && low.x <= 6u;
}
public bool plm_type_ref(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 1u) return pev_scalar_is_valid(reference.y);
    uint4 low; uint4 high;
    return reference.x == 3u && plm_node(reference.y, false, low, high) && low.x <= 4u;
}
public bool plm_constant_value(uint row, out uint3 value)
{
    value = uint3(0u, 0u, 0u); uint4 low; uint4 high;
    if (!plm_node(row, false, low, high) || low.x != 6u ||
        any(high != uint4(0u, 0u, 0u, 0u)) || !constant_value_is_valid(low.yzw)) return false;
    value = low.yzw; return true;
}
public bool plm_constant_projection(uint row, out uint target, out uint2 child)
{
    target = 0u; child = uint2(0u, PEV_INVALID); uint4 low; uint4 high;
    if (!plm_node(row, false, low, high) || low.x != 5u || !scalar_is_integer(low.y) ||
        any(low.zw != uint2(0u, 0u)) || any(high.zw != uint2(0u, 0u)) ||
        high.x < 0x80000001u || high.x > 0x80000003u || high.y == PEV_INVALID) return false;
    target = low.y; child = uint2(high.x & 0x7fffffffu, high.y); return true;
}
public bool plm_constant_ref(uint2 reference)
{
    uint3 value; uint target; uint2 child;
    return (reference.x == 0x80000001u && plm_constant_value(reference.y, value)) ||
        (reference.x == 0x80000003u && plm_constant_projection(reference.y, target, child));
}
public bool plm_constant_count(uint2 reference, out uint count)
{
    count = 0u; uint3 value;
    return reference.x == 0x80000001u && plm_constant_value(reference.y, value) &&
        constant_value_to_count(value, count);
}
public bool plm_child(uint4 low, uint4 high, uint ordinal, out uint2 reference, out uint domain)
{
    reference = uint2(0u, PEV_INVALID); domain = PEV_ADMITTED_DOMAIN_TYPE;
    if (low.x == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_EITHER;
        if (low.w > 32u || ordinal >= low.w || low.z > plm_used(1u) || low.w > plm_used(1u) - low.z ||
            !plm_read2(1u, low.z + ordinal, 0u, false, reference)) return false;
        return plm_type_ref(reference) || plm_constant_ref(reference);
    }
    if (low.x == 5u && ordinal == 0u)
    { domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.xy; return plm_constant_ref(reference); }
    if (low.x == 2u && ordinal == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.zw;
        return plm_constant_ref(reference);
    }
    if (low.x >= 2u && low.x <= 4u && ordinal == 0u)
    { reference = high.xy; return plm_type_ref(reference); }
    return false;
}
public struct NativeLayoutTypeGraph : IParameterScopedTypeGraph, IProofNormalizationGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return plm_constant_value(row, value); }
    public static uint constant_parameter_scalar(uint reference) { return 0u; }
    public static bool constant_projection(uint row, out uint target, out uint2 child)
    { return plm_constant_projection(row, target, child); }
    public static bool parameter_is_valid(uint reference, bool constant) { return false; }
    public static bool substitute_type_parameter(uint env, uint parameter, out uint tag, out uint payload)
    { tag = 0u; payload = PEV_INVALID; return false; }
    public static bool substitute_constant_parameter(uint env, uint parameter, out uint kind, out uint value)
    { kind = 0u; value = PEV_INVALID; return false; }
    public static bool node(uint row, out uint4 low, out uint4 high)
    { return plm_node(row, false, low, high); }
    public static bool child(uint4 low, uint4 high, uint ordinal, out uint2 reference, out uint domain)
    { return plm_child(low, high, ordinal, reference, domain); }
    public static uint metadata(uint instance, uint field)
    {
        uint4 low; uint4 high;
        if (!plm_node(instance, false, low, high) || low.x > 4u) return PEV_INVALID;
        if (field == 0u) return low.x;
        if (field == 1u) return low.x == 1u ? low.y : PEV_INVALID;
        if (field == 2u) return low.x == 1u ? low.w : 0u;
        if (field == 3u) return high.x;
        if (field == 4u) return high.y;
        if (field == 5u) return low.x == 2u ? high.z & 0x7fffffffu : PEV_INVALID;
        if (field == 6u) return low.x == 2u ? high.w : PEV_INVALID;
        return PEV_INVALID;
    }
    public static bool argument(uint instance, uint ordinal, out uint tag, out uint payload)
    {
        tag = 0u; payload = PEV_INVALID;
        uint4 low; uint4 high; uint2 reference; uint domain;
        if (!plm_node(instance, false, low, high) || low.x != 1u ||
            !plm_child(low, high, ordinal, reference, domain)) return false;
        tag = reference.x; payload = reference.y; return true;
    }
}
public struct NativeLayoutSink : IProofNormalizationSink
{
    public static bool begin_node(uint row, uint4 low, uint4 high)
    {
        return plm_write4(0u, row, 0u, low) && plm_write4(0u, row, 4u, high) &&
            plm_write4(4u, row, 0u, uint4(0u, 0u, 0u, PEV_INVALID));
    }
    public static bool set_child(uint row, uint ordinal, uint2 reference)
    {
        uint4 low; uint4 high;
        if (!plm_node(row, true, low, high)) return false;
        if (low.x == 1u)
            return low.w <= 32u && ordinal < low.w && low.z <= PEV_INVALID - ordinal &&
                plm_write2(1u, low.z + ordinal, 0u, reference);
        if (low.x < 2u || low.x > 5u || ordinal > (low.x == 2u ? 1u : 0u)) return false;
        return plm_write2(0u, row, ordinal == 0u ? 4u : 6u, reference);
    }
}
public struct NativeLayoutCheckSink : IProofNormalizationSink
{
    public static bool begin_node(uint row, uint4 expected, uint4 unused)
    {
        uint4 low; uint4 high;
        if (!plm_node(row, true, low, high) || any(low != expected)) return false;
        return (low.x == 1u || low.x == 6u) ? all(high == uint4(0u, 0u, 0u, 0u)) :
            (low.x == 2u || (high.z == 0u && high.w == 0u));
    }
    public static bool set_child(uint row, uint ordinal, uint2 expected)
    {
        uint4 low; uint4 high; uint2 actual;
        if (!plm_node(row, true, low, high)) return false;
        if (low.x == 1u)
            return low.w <= 32u && ordinal < low.w && low.z <= PEV_INVALID - ordinal &&
                plm_read2(1u, low.z + ordinal, 0u, true, actual) && all(actual == expected);
        if (low.x < 2u || low.x > 5u || ordinal > (low.x == 2u ? 1u : 0u)) return false;
        return all((ordinal == 0u ? high.xy : high.zw) == expected);
    }
}
public struct NativeLayoutRecipeBindings : IProofNormalizationBindings
{
    public static bool replacement(uint nominal_node, uint parameter, bool constant, out uint2 reference)
    {
        reference = uint2(0u, PEV_INVALID);
        uint4 node; uint4 children; uint recipe; uint4 row; uint4 tail;
        uint4 owner; uint4 span; uint4 atom;
        if (!plm_node(nominal_node, false, node, children) || node.x != 1u ||
            !plr_recipe_for_nominal(node.y, recipe) || !plr_read_recipe(recipe, row, tail) ||
            !pev_read_admitted_owner(row.y, owner, span) ||
            !pev_read_admitted_parameter(parameter, atom) || atom.y != owner.x ||
            atom.z != (constant ? 1u : 0u) || node.w != span.y || node.w > 32u)
            return false;
        // The ordered owner span is the nominal operand order. Source ordinal
        // remains part of the exact atom identity; accepted headers need not
        // have densely numbered ordinals. Domain slots are never identity.
        for (uint position = 0u; position < span.y; position++)
        {
            uint4 parameter_row;
            if (!pev_read4(3u, span.x + position, 0u, parameter_row) || parameter_row.x != row.y)
                return false;
            if (parameter_row.y != parameter) continue;
            uint domain;
            if (parameter_row.w != atom.z || !plm_child(node, children, position, reference, domain))
                return false;
            uint3 value;
            return constant ? reference.x == 0x80000001u &&
                plm_constant_value(reference.y, value) &&
                value.x == pev_constant_parameter_scalar(parameter) : plm_type_ref(reference);
        }
        return false;
    }
}

// Count, emit, and exact-check share the existing one-shot transform. All three
// operate on immutable source/replacement graphs. The exclusive job publishes
// new row counts only after the check; unrelated invocations cannot read it.
public EvidenceStatus plm_copy_closed_root<Source : IProofNormalizationGraph,
    Replacement : IProofNormalizationGraph, Bindings : IProofNormalizationBindings>(
    uint2 source, uint environment, uint owner, out uint2 result)
{
    result = uint2(0u, PEV_INVALID);
    ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
    ProofNormalizationCounts counted; uint2 unused; bool closed;
    EvidenceStatus status = pev_normalize_proof_root<Source, Replacement, Bindings, NativeLayoutSink>(
        source, environment, owner, PEV_ADMITTED_DOMAIN_TYPE, false, reservation, unused, closed, counted);
    if (status.state != PEV_VALID) return status;
    if (!closed) return pev_invalid(173u, source.y, PEV_INVALID);
    status = plm_charge(counted.visits); if (status.state != PEV_VALID) return status;
    status = plm_reserve(0u, counted.nodes, reservation.first_node); if (status.state != PEV_VALID) return status;
    status = plm_reserve(1u, counted.edges, reservation.first_edge); if (status.state != PEV_VALID) return status;
    reservation.node_count = counted.nodes; reservation.edge_count = counted.edges;
    ProofNormalizationCounts emitted;
    status = pev_normalize_proof_root<Source, Replacement, Bindings, NativeLayoutSink>(
        source, environment, owner, PEV_ADMITTED_DOMAIN_TYPE, true, reservation, result, closed, emitted);
    if (status.state != PEV_VALID) return status;
    uint2 checked; ProofNormalizationCounts verified;
    status = pev_normalize_proof_root<Source, Replacement, Bindings, NativeLayoutCheckSink>(
        source, environment, owner, PEV_ADMITTED_DOMAIN_TYPE, true, reservation, checked, closed, verified);
    if (status.state != PEV_VALID) return status;
    if (!closed || any(checked != result)) return pev_invalid(174u, source.y, result.y);
    program_evidence_native_layout_work[13u] = reservation.first_node + reservation.node_count;
    program_evidence_native_layout_work[14u] = reservation.first_edge + reservation.edge_count;
    return pev_ok();
}
