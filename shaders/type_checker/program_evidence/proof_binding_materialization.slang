import primitive_types;
import constant_value;
import type_checker.program_evidence.constant_atoms;
// Binding-owned prefixes are private until the complete substitution wave is
// checked. Its exact source is reconstructed from the admitted goal match.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.proof_goal_admission;
import type_checker.owned_type_constraint_contract;

public bool pps_binding_node_span(uint4 allocation, bool pending)
{
    uint4 nodes; uint accepted;
    if (any(allocation.zw != uint2(0u, 0u)) || allocation.y >= PEV_DEPTH_LIMIT ||
        !pps_descriptor(PPS_TERM_NODES, nodes, accepted)) return false;
    if (allocation.y == 0u) return allocation.x == 0u;
    uint limit = pending ? nodes.y : nodes.w;
    return allocation.x < limit && allocation.y <= limit - allocation.x &&
        (!pending || allocation.x >= nodes.w);
}

// Replay reads exactly the owning binding's checked allocation. This sink has
// no matching/equality capability and cannot publish admission itself.
public struct OwnedBindingCheckSink : IProofNormalizationSink
{
    public static bool read(uint row, out uint4 low, out uint4 high)
    {
        low = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); high = low;
        uint admitted;
        return pps_count(PPS_TERM_NODES, admitted) && (row < admitted
            ? pps_read8(PPS_TERM_NODES, row, low, high)
            : pps_read_pending8(PPS_TERM_NODES, row, low, high));
    }
    public static bool begin_node(uint mode, uint row, uint4 expected, uint4 unused)
    {
        uint4 low; uint4 high;
        if (!read(row, low, high) || any(low != expected)) return false;
        return low.x == 6u ? all(high == uint4(0u, 0u, 0u, 0u)) :
            low.x == 5u && all(high.zw == uint2(0u, 0u));
    }
    public static bool set_child(uint mode, uint row, uint ordinal, uint2 expected)
    {
        uint4 low; uint4 high;
        return ordinal == 0u && read(row, low, high) && low.x == 5u && all(high.xy == expected);
    }
}

// The terminal/root is already in the admitted goal namespace (side1). Each
// target owns one row; folding to Node6 does not erase allocation ownership of
// earlier steps. Exact replay checks those rows even when they become unreachable.
public EvidenceStatus pps_materialize_binding_request<Sink : IProofNormalizationSink>(
    OwnedConstraintBindingRequest request, uint parameter, uint visible_owner,
    bool require_closed, uint4 allocation, out uint2 normalized, out bool closed)
{
    normalized = uint2(0u, PEV_INVALID); closed = false;
    uint4 parameter_atom;
    if (request.reference.x != 1u || request.target_count >= PEV_DEPTH_LIMIT ||
        request.target_count != allocation.y || any(allocation.zw != uint2(0u, 0u)) ||
        (allocation.y == 0u && allocation.x != 0u) ||
        !pev_read_admitted_parameter(parameter, parameter_atom) || parameter_atom.z > 1u)
        return pev_invalid(68u, parameter, request.reference.z);
    bool constant = parameter_atom.z == 1u;
    uint2 leaf = request.reference.yz;
    if ((!constant && request.target_count != 0u) ||
        (constant && leaf.x != 0x80000001u && leaf.x != 0x80000002u))
        return pev_invalid(68u, parameter, leaf.y);
    EvidenceStatus status = pps_admit_term(leaf, visible_owner,
        constant ? PEV_ADMITTED_DOMAIN_CONSTANT : PEV_ADMITTED_DOMAIN_TYPE, require_closed, closed);
    if (status.state != PEV_VALID) return status;
    uint3 value = uint3(0u, 0u, 0u);
    bool concrete = constant && leaf.x == 0x80000001u;
    uint scalar = 0u;
    if (constant)
    {
        scalar = pps_constant_reference_scalar(leaf);
        if (concrete && !pps_constant_value(leaf.y, value)) return pev_invalid(68u, parameter, leaf.y);
        uint result_scalar = request.target_count == 0u ? scalar : owned_constraint_target(request.targets, 0u);
        if (result_scalar != pev_constant_parameter_scalar(parameter)) return pev_invalid(68u, parameter, scalar);
    }
    normalized = leaf;
    for (uint remaining = request.target_count; remaining != 0u; remaining--)
    {
        uint index = remaining - 1u; uint target = owned_constraint_target(request.targets, index);
        if (!scalar_is_integer(scalar) || !scalar_is_integer(target) || allocation.x > PEV_INVALID - index)
            return pev_invalid(68u, parameter, target);
        uint row = allocation.x + index;
        if (concrete)
        {
            uint count; uint3 fitted;
            if (!constant_value_to_count(value, count) || !constant_value_from_count(count, target, fitted))
                return pev_invalid(66u, parameter, target);
            if (!Sink.begin_node(0u, row, uint4(6u, fitted), uint4(0u, 0u, 0u, 0u)))
                return pev_invalid(68u, parameter, row);
            value = fitted; normalized = uint2(0x80000001u, row);
        }
        else
        {
            if (!Sink.begin_node(0u, row, uint4(5u, target, 0u, 0u), uint4(0u, 0u, 0u, 0u)) ||
                !Sink.set_child(0u, row, 0u, normalized)) return pev_invalid(68u, parameter, row);
            normalized = uint2(0x80000003u, row);
        }
        scalar = target;
    }
    return pev_ok();
}
