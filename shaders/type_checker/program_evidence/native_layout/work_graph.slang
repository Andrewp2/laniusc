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
    // Work node rows are eight words wide: one check covers both halves.
    bool read = plm_read8(0u, row, pending, low, high);
    return read & (low.x >= 1u) & (low.x <= 6u);
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
    // A nominal operand may be either kind; a projection's value and an
    // array's length are constants; the other single children are types.
    // Each reference check has one call site.
    bool constant_child = (low.x == 5u && ordinal == 0u) || (low.x == 2u && ordinal == 1u);
    bool type_child = low.x >= 2u && low.x <= 4u && ordinal == 0u;
    if (low.x == 1u)
    {
        domain = PEV_ADMITTED_DOMAIN_EITHER;
        if (low.w > 32u || ordinal >= low.w || low.z > plm_used(1u) || low.w > plm_used(1u) - low.z ||
            !plm_read2(1u, low.z + ordinal, 0u, false, reference)) return false;
    }
    else if (constant_child)
    { domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = select(bool2(ordinal == 0u, ordinal == 0u), high.xy, high.zw); }
    else if (type_child) reference = high.xy;
    else return false;
    return (!constant_child && plm_type_ref(reference)) || (!type_child && plm_constant_ref(reference));
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
        // Same field map as admitted input nodes (pev_node_row_field).
        uint4 low; uint4 high;
        bool read = plm_node(instance, false, low, high);
        return select(read & (low.x <= 4u), pev_node_row_field(low, high, field), PEV_INVALID);
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
// Mode NATIVE_LAYOUT_SINK_WRITE writes each emitted row; mode
// NATIVE_LAYOUT_SINK_CHECK compares the rows that the write pass produced.
static const uint NATIVE_LAYOUT_SINK_WRITE = 1u;
static const uint NATIVE_LAYOUT_SINK_CHECK = 2u;
public struct NativeLayoutSink : IProofNormalizationSink
{
    public static bool begin_node(uint mode, uint row, uint4 low, uint4 high)
    {
        if (mode != NATIVE_LAYOUT_SINK_CHECK)
            return plm_write4(0u, row, 0u, low) && plm_write4(0u, row, 4u, high) &&
                plm_write4(4u, row, 0u, uint4(0u, 0u, 0u, PEV_INVALID));
        uint4 expected = low; uint4 actual_high;
        if (!plm_node(row, true, low, actual_high) || any(low != expected)) return false;
        return (low.x == 1u || low.x == 6u) ? all(actual_high == uint4(0u, 0u, 0u, 0u)) :
            (low.x == 2u || (actual_high.z == 0u && actual_high.w == 0u));
    }
    public static bool set_child(uint mode, uint row, uint ordinal, uint2 reference)
    {
        uint4 low; uint4 high;
        if (!plm_node(row, true, low, high)) return false;
        bool check = mode == NATIVE_LAYOUT_SINK_CHECK;
        if (low.x == 1u)
        {
            if (low.w > 32u || ordinal >= low.w || low.z > PEV_INVALID - ordinal) return false;
            if (!check) return plm_write2(1u, low.z + ordinal, 0u, reference);
            uint2 actual;
            return plm_read2(1u, low.z + ordinal, 0u, true, actual) && all(actual == reference);
        }
        if (low.x < 2u || low.x > 5u || ordinal > (low.x == 2u ? 1u : 0u)) return false;
        if (!check) return plm_write2(0u, row, ordinal == 0u ? 4u : 6u, reference);
        return all((ordinal == 0u ? high.xy : high.zw) == reference);
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
public EvidenceStatus plm_copy_closed_root<Graphs : IProofNormalizationPair,
    Bindings : IProofNormalizationBindings>(
    uint2 source, uint environment, uint owner, out uint2 result)
{
    result = uint2(0u, PEV_INVALID);
    ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
    // Pass 0 counts, pass 1 writes (sink mode WRITE), pass 2 checks the written
    // rows (sink mode CHECK), all through one traversal site.
    [loop]
    for (uint pass = 0u; pass < 3u; pass++)
    {
        reservation.sink_mode = pass;
        ProofNormalizationCounts measured; uint2 normalized; bool closed;
        EvidenceStatus status = pev_normalize_proof_root<Graphs, Bindings, NativeLayoutSink>(
            source, environment, owner, PEV_ADMITTED_DOMAIN_TYPE, pass != 0u, reservation,
            normalized, closed, measured);
        if (status.state != PEV_VALID) return status;
        if (pass == 0u)
        {
            if (!closed) return pev_invalid(173u, source.y, PEV_INVALID);
            status = plm_charge(measured.visits); if (status.state != PEV_VALID) return status;
            status = plm_reserve(0u, measured.nodes, reservation.first_node); if (status.state != PEV_VALID) return status;
            status = plm_reserve(1u, measured.edges, reservation.first_edge); if (status.state != PEV_VALID) return status;
            reservation.node_count = measured.nodes; reservation.edge_count = measured.edges;
        }
        else if (pass == 1u) result = normalized;
        else if (!closed || any(normalized != result)) return pev_invalid(174u, source.y, result.y);
    }
    program_evidence_native_layout_work[13u] = reservation.first_node + reservation.node_count;
    program_evidence_native_layout_work[14u] = reservation.first_edge + reservation.edge_count;
    return pev_ok();
}
