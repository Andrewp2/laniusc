import shared.semantics.primitive_types;
import shared.semantics.constant_value;
import type_checker.trait_solver.constant_atoms;
// The bindings of a matched implementation, written as proof-store terms.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.proof_term_normalization;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.owned_type_constraint_contract;

// A term already in the proof store's namespace: its scope and closure.
public SolverStatus pps_admit_term(uint2 reference, uint owner, uint domain,
    bool require_closed, out bool closed)
{
    closed = false; uint2 unpublished; ProofNormalizationCounts counts;
    ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
    SolverStatus status = ts_normalize_proof_root<SameProofNormalizationGraph<SolverProofTermGraph>,
        NoProofNormalizationBindings, NoProofNormalizationSink>(
        reference, TS_INVALID, owner, domain, false, reservation, unpublished, closed, counts);
    if (status.state != TS_VALID) return status;
    if (require_closed && !closed) return ts_invalid(10u, reference.y, owner);
    return ts_ok();
}

// The terminal/root is already in the admitted goal namespace (side1). Each
// target owns one row; folding to Node6 does not erase allocation ownership of
// earlier steps.
public SolverStatus pps_materialize_binding_request<Sink : IProofNormalizationSink>(
    OwnedConstraintBindingRequest request, uint parameter, uint visible_owner,
    bool require_closed, uint4 allocation, out uint2 normalized, out bool closed)
{
    normalized = uint2(0u, TS_INVALID); closed = false;
    uint2 leaf; bool constant;
    SolverStatus status = pps_binding_request_leaf(request, parameter, allocation, leaf, constant);
    if (status.state != TS_VALID) return status;
    status = pps_admit_term(leaf, visible_owner,
        constant ? TS_ADMITTED_DOMAIN_CONSTANT : TS_ADMITTED_DOMAIN_TYPE, require_closed, closed);
    if (status.state != TS_VALID) return status;
    return pps_binding_request_targets<Sink>(request, parameter, allocation, leaf, constant,
        normalized);
}
// The request's leaf, admitted in the constant domain for a constant parameter.
public SolverStatus pps_binding_request_leaf(OwnedConstraintBindingRequest request,
    uint parameter, uint4 allocation, out uint2 leaf, out bool constant)
{
    leaf = request.reference.yz; constant = false;
    uint4 parameter_atom;
    if (request.reference.x != 1u || request.target_count >= TS_DEPTH_LIMIT ||
        request.target_count != allocation.y || any(allocation.zw != uint2(0u, 0u)) ||
        (allocation.y == 0u && allocation.x != 0u) ||
        !ts_read_admitted_parameter(parameter, parameter_atom) || parameter_atom.z > 1u)
        return ts_invalid(68u, parameter, request.reference.z);
    constant = parameter_atom.z == 1u;
    if ((!constant && request.target_count != 0u) ||
        (constant && leaf.x != 0x80000001u && leaf.x != 0x80000002u))
        return ts_invalid(68u, parameter, leaf.y);
    return ts_ok();
}
// After the leaf's admission: its scalar, then each owned target row.
public SolverStatus pps_binding_request_targets<Sink : IProofNormalizationSink>(
    OwnedConstraintBindingRequest request, uint parameter, uint4 allocation, uint2 leaf,
    bool constant, out uint2 normalized)
{
    normalized = uint2(0u, TS_INVALID);
    uint3 value = uint3(0u, 0u, 0u);
    bool concrete = constant && leaf.x == 0x80000001u;
    uint scalar = 0u;
    if (constant)
    {
        scalar = pps_constant_reference_scalar(leaf);
        if (concrete && !pps_constant_value(leaf.y, value)) return ts_invalid(68u, parameter, leaf.y);
        uint result_scalar = request.target_count == 0u ? scalar : owned_constraint_target(request.targets, 0u);
        if (result_scalar != ts_constant_parameter_scalar(parameter)) return ts_invalid(68u, parameter, scalar);
    }
    normalized = leaf;
    for (uint remaining = request.target_count; remaining != 0u; remaining--)
    {
        uint index = remaining - 1u; uint target = owned_constraint_target(request.targets, index);
        if (!scalar_is_integer(scalar) || !scalar_is_integer(target) || allocation.x > TS_INVALID - index)
            return ts_invalid(68u, parameter, target);
        uint row = allocation.x + index;
        if (concrete)
        {
            uint count; uint3 fitted;
            if (!constant_value_to_count(value, count) || !constant_value_from_count(count, target, fitted))
                return ts_invalid(66u, parameter, target);
            if (!Sink.begin_node(0u, row, uint4(6u, fitted), uint4(0u, 0u, 0u, 0u)))
                return ts_invalid(68u, parameter, row);
            value = fitted; normalized = uint2(0x80000001u, row);
        }
        else
        {
            if (!Sink.begin_node(0u, row, uint4(5u, target, 0u, 0u), uint4(0u, 0u, 0u, 0u)) ||
                !Sink.set_child(0u, row, 0u, normalized)) return ts_invalid(68u, parameter, row);
            normalized = uint2(0x80000003u, row);
        }
        scalar = target;
    }
    return ts_ok();
}
