import primitive_types;
import type_checker.program_evidence.constant_atoms;
// Copy an admitted root into an independently owned normalized store. Type
// nodes, typed literal nodes, and pending count projections all acquire this
// store's namespace. Parameter identities remain exact immutable catalog atoms.
// A substitution crosses to ReplacementGraph exactly once.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.packed_graph;
import constant_value;

public interface IProofNormalizationGraph
{
    static bool node(uint row, out uint4 low, out uint4 high);
    static bool child(uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain);
    // The graph owns this literal namespace. Input packets use Atom8 category12;
    // normalized stores use Node8 kind6. A row number never selects the namespace.
    static bool constant_value(uint row, out uint3 value);
}
public interface IProofNormalizationBindings
{
    static bool replacement(uint environment, uint parameter, bool constant,
        out uint2 reference);
}
public interface IProofNormalizationSink
{
    static bool begin_node(uint row, uint4 low, uint4 high);
    static bool set_child(uint row, uint ordinal, uint2 reference);
}
public struct ProofNormalizationReservation
{
    public uint first_node; public uint node_count;
    public uint first_edge; public uint edge_count;
}
public struct ProofNormalizationCounts
{
    public uint nodes; public uint edges; public uint visits;
}
public struct InputProofNormalizationGraph : IProofNormalizationGraph
{
    public static bool node(uint row, out uint4 low, out uint4 high)
    { return pev_read_admitted_node(row, low, high); }
    public static bool child(uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain)
    { return pev_read_admitted_child(low, high, ordinal, reference, domain); }
    public static bool constant_value(uint row, out uint3 value)
    { return pev_constant_atom_value(row, value); }
}
public struct InputProofNormalizationBindings : IProofNormalizationBindings
{
    public static bool replacement(uint environment, uint parameter, bool constant,
        out uint2 reference)
    {
        reference = uint2(0u, PEV_INVALID);
        if (!pev_admitted_parameter_has_domain(parameter, constant) ||
            !pev_admitted_environment_binding(environment, parameter, reference)) return false;
        return constant ? pev_admitted_constant_reference_shape(reference) :
            pev_admitted_type_reference_shape(reference);
    }
}

// Read only the result domain here. Traversal below validates the complete
// replacement and every pending fit in its own immutable namespace.
uint normalized_reference_scalar<Graph : IProofNormalizationGraph>(uint2 reference)
{
    if (reference.x == 0x80000001u)
    { uint3 value; return Graph.constant_value(reference.y, value) && constant_value_is_valid(value) ? value.x : 0u; }
    if (reference.x == 0x80000002u) return pev_constant_parameter_scalar(reference.y);
    uint4 low; uint4 high;
    return reference.x == 0x80000003u && Graph.node(reference.y, low, high) && low.x == 5u &&
        scalar_is_integer(low.y) ? low.y : 0u;
}

// Count and emit perform the same bounded traversal and value checks. Emission
// never publishes a parent child-reference until that child's constant fitting
// has finished. Failed output remains an unpublished suffix.
public EvidenceStatus pev_normalize_proof_root<
    SourceGraph : IProofNormalizationGraph,
    ReplacementGraph : IProofNormalizationGraph,
    Bindings : IProofNormalizationBindings,
    Sink : IProofNormalizationSink>(
    uint2 input, uint environment, uint visible_owner, uint domain,
    bool emit, ProofNormalizationReservation reservation,
    out uint2 normalized, out bool closed, out ProofNormalizationCounts measured)
{
    normalized = uint2(0u, PEV_INVALID); closed = false;
    measured = (ProofNormalizationCounts)0;
    if (domain > PEV_ADMITTED_DOMAIN_CONSTANT) return pev_invalid(4u, input.y, domain);
    if (emit && (reservation.first_node == PEV_INVALID || reservation.first_edge == PEV_INVALID ||
        reservation.node_count > PEV_INVALID - reservation.first_node ||
        reservation.edge_count > PEV_INVALID - reservation.first_edge))
        return pev_invalid(1u, input.y, PEV_INVALID);

    uint4 references[PEV_DEPTH_LIMIT]; // tag, row, environment, source/replacement side
    uint4 node_low[PEV_DEPTH_LIMIT]; uint4 node_high[PEV_DEPTH_LIMIT];
    uint next[PEV_DEPTH_LIMIT]; uint counts[PEV_DEPTH_LIMIT];
    uint domains[PEV_DEPTH_LIMIT]; uint output_nodes[PEV_DEPTH_LIMIT];
    uint2 output_refs[PEV_DEPTH_LIMIT]; uint2 projection_children[PEV_DEPTH_LIMIT];
    // x is a constant's declared scalar even when it remains symbolic. The
    // single child of a projection supplies its value here at child completion.
    uint3 values[PEV_DEPTH_LIMIT]; uint concrete[PEV_DEPTH_LIMIT];
    bool is_closed = true;
    uint depth = 0u;
    references[0u] = uint4(input.x, input.y, environment, 0u);
    next[0u] = PEV_INVALID; domains[0u] = domain;
    [loop]
    for (;;)
    {
        uint4 reference = references[depth];
        if (next[depth] == PEV_INVALID)
        {
            if (measured.visits == PEV_VISIT_LIMIT)
                return pev_limit(7u, input.y, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
            measured.visits++;
            bool constant_parameter = reference.x == 0x80000002u;
            if (reference.x == 2u || constant_parameter)
            {
                if (!pev_admitted_parameter_has_domain(reference.y, constant_parameter))
                    return pev_invalid(4u, input.y, reference.y);
                if (reference.z != PEV_INVALID)
                {
                    uint2 replacement;
                    if (reference.w != 0u || !Bindings.replacement(reference.z, reference.y,
                        constant_parameter, replacement)) return pev_invalid(9u, input.y, reference.y);
                    bool replacement_constant = replacement.x >= 0x80000001u && replacement.x <= 0x80000003u;
                    if (replacement_constant != constant_parameter ||
                        (constant_parameter && normalized_reference_scalar<ReplacementGraph>(replacement) !=
                            pev_constant_parameter_scalar(reference.y)))
                        return pev_invalid(4u, input.y, reference.y);
                    reference = uint4(replacement.x, replacement.y, PEV_INVALID, 1u);
                }
            }
            bool constant = reference.x >= 0x80000001u && reference.x <= 0x80000003u;
            if (reference.y == PEV_INVALID ||
                (domains[depth] == PEV_ADMITTED_DOMAIN_TYPE && constant) ||
                (domains[depth] == PEV_ADMITTED_DOMAIN_CONSTANT && !constant))
                return pev_invalid(4u, input.y, reference.y);
            next[depth] = 0u; counts[depth] = 0u;
            output_nodes[depth] = PEV_INVALID; output_refs[depth] = reference.xy;
            values[depth] = uint3(0u, 0u, 0u); concrete[depth] = 0u;
            node_low[depth] = uint4(0u, 0u, 0u, 0u); node_high[depth] = node_low[depth];
            bool allocate = false;
            if (reference.x == 1u)
            {
                if (!pev_scalar_is_valid(reference.y)) return pev_invalid(4u, input.y, reference.y);
            }
            else if (reference.x == 2u || reference.x == 0x80000002u)
            {
                if (!pev_admitted_parameter_has_domain(reference.y, constant) ||
                    !pev_admitted_parameter_visible(reference.y, visible_owner))
                    return pev_invalid(3u, input.y, reference.y);
                if (constant)
                {
                    values[depth].x = pev_constant_parameter_scalar(reference.y);
                    if (values[depth].x == 0u) return pev_invalid(4u, input.y, reference.y);
                }
                is_closed = false;
            }
            else if (reference.x == 0x80000001u)
            {
                uint3 value;
                bool read = reference.w == 0u ? SourceGraph.constant_value(reference.y, value) :
                    ReplacementGraph.constant_value(reference.y, value);
                if (!read || !constant_value_is_valid(value)) return pev_invalid(4u, input.y, reference.y);
                values[depth] = value; concrete[depth] = 1u;
                node_low[depth] = uint4(6u, value); allocate = true;
            }
            else if (reference.x == 3u || reference.x == 0x80000003u)
            {
                [loop]
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (all(references[ancestor] == reference)) return pev_invalid(5u, input.y, reference.y);
                uint4 low; uint4 high;
                bool read = reference.w == 0u ? SourceGraph.node(reference.y, low, high) :
                    ReplacementGraph.node(reference.y, low, high);
                if (!read || (constant ? low.x != 5u : low.x < 1u || low.x > 4u) ||
                    (low.x == 1u && (low.w > 32u || !pev_nominal_is_valid(low.y))) ||
                    (low.x == 5u && (!scalar_is_integer(low.y) || any(low.zw != uint2(0u, 0u)))))
                    return pev_invalid(4u, input.y, reference.y);
                node_low[depth] = low; node_high[depth] = high;
                counts[depth] = low.x == 1u ? low.w : (low.x == 2u ? 2u : 1u);
                allocate = true;
            }
            else return pev_invalid(4u, input.y, reference.y);
            if (allocate)
            {
                uint4 low = node_low[depth];
                uint edge_count = low.x == 1u ? low.w : 0u;
                if (measured.nodes == PEV_INVALID || edge_count > PEV_INVALID - measured.edges)
                    return pev_limit(64u, input.y, PEV_INVALID, PEV_INVALID - 1u);
                if (emit && (measured.nodes >= reservation.node_count ||
                    measured.edges > reservation.edge_count || edge_count > reservation.edge_count - measured.edges))
                    return pev_invalid(65u, input.y, measured.nodes);
                uint output_node = emit ? reservation.first_node + measured.nodes : measured.nodes;
                uint output_edge = emit ? reservation.first_edge + measured.edges : measured.edges;
                measured.nodes++; measured.edges += edge_count;
                output_nodes[depth] = output_node;
                output_refs[depth] = uint2(constant ? reference.x : 3u, output_node);
                if (emit)
                {
                    uint4 output_low = low.x == 1u ? uint4(1u, low.y, edge_count == 0u ? 0u : output_edge, edge_count) :
                        low.x == 6u ? low : uint4(low.x, low.x == 5u ? low.y : 0u, 0u, 0u);
                    if (low.x != 5u && !Sink.begin_node(output_node, output_low, uint4(0u, 0u, 0u, 0u)))
                        return pev_invalid(1u, input.y, output_node);
                }
            }
            references[depth] = reference;
        }
        if (next[depth] == counts[depth])
        {
            // A pending projection retains its complete expression. A concrete
            // projection discharges both count-domain and target-range checks
            // on GPU and becomes an owned exact literal before parent publish.
            if (node_low[depth].x == 5u)
            {
                uint target = node_low[depth].y;
                if (!scalar_is_integer(values[depth].x)) return pev_invalid(4u, input.y, reference.y);
                if (concrete[depth] != 0u)
                {
                    uint count; uint3 fitted;
                    if (!constant_value_to_count(values[depth], count) ||
                        !constant_value_from_count(count, target, fitted)) return pev_invalid(66u, input.y, reference.y);
                    values[depth] = fitted;
                    output_refs[depth].x = 0x80000001u;
                    if (emit && !Sink.begin_node(output_nodes[depth], uint4(6u, fitted), uint4(0u, 0u, 0u, 0u)))
                        return pev_invalid(1u, input.y, output_nodes[depth]);
                }
                else
                {
                    values[depth].x = target;
                    if (emit && (!Sink.begin_node(output_nodes[depth], uint4(5u, target, 0u, 0u), uint4(0u, 0u, 0u, 0u)) ||
                        !Sink.set_child(output_nodes[depth], 0u, projection_children[depth])))
                        return pev_invalid(1u, input.y, output_nodes[depth]);
                }
            }
            if (depth == 0u)
            {
                if (emit && (measured.nodes != reservation.node_count || measured.edges != reservation.edge_count))
                    return pev_invalid(65u, input.y, measured.nodes);
                if (emit) normalized = output_refs[0u];
                closed = is_closed; return pev_ok();
            }
            uint parent = depth - 1u;
            uint ordinal = next[parent] - 1u;
            if (node_low[parent].x == 5u)
            {
                values[parent] = values[depth]; concrete[parent] = concrete[depth];
                projection_children[parent] = output_refs[depth];
            }
            if (node_low[parent].x == 2u && ordinal == 1u)
            {
                if (!scalar_is_integer(values[depth].x)) return pev_invalid(4u, input.y, reference.y);
                uint count;
                if (concrete[depth] != 0u && !constant_value_to_count(values[depth], count))
                    return pev_invalid(66u, input.y, reference.y);
            }
            if (emit && node_low[parent].x != 5u &&
                !Sink.set_child(output_nodes[parent], ordinal, output_refs[depth]))
                return pev_invalid(1u, input.y, output_nodes[parent]);
            depth--; continue;
        }
        uint ordinal = next[depth]++;
        uint2 child; uint child_domain;
        bool read = reference.w == 0u ?
            SourceGraph.child(node_low[depth], node_high[depth], ordinal, child, child_domain) :
            ReplacementGraph.child(node_low[depth], node_high[depth], ordinal, child, child_domain);
        if (!read) return pev_invalid(4u, input.y, reference.y);
        if (depth + 1u == PEV_DEPTH_LIMIT) return pev_limit(6u, input.y, depth + 2u, PEV_DEPTH_LIMIT);
        depth++;
        references[depth] = uint4(child.x, child.y, reference.z, reference.w);
        domains[depth] = child_domain; next[depth] = PEV_INVALID;
    }
}
