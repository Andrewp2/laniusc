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
import thread_scratch;

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
// mode is the reservation's sink_mode: a sink with several emission passes
// (write, then check what was written) selects the pass from it.
public interface IProofNormalizationSink
{
    static bool begin_node(uint mode, uint row, uint4 low, uint4 high);
    static bool set_child(uint mode, uint row, uint ordinal, uint2 reference);
}
public struct ProofNormalizationReservation
{
    public uint first_node; public uint node_count;
    public uint first_edge; public uint edge_count;
    public uint sink_mode;
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
// The capabilities of a walk with no environment (PEV_INVALID) that does not
// emit: it substitutes no reference, so it never asks for a replacement, and
// it writes no row. Neither is ever called; a misuse fails closed.
public struct NoProofNormalizationBindings : IProofNormalizationBindings
{
    public static bool replacement(uint environment, uint parameter, bool constant,
        out uint2 reference)
    { reference = uint2(0u, PEV_INVALID); return false; }
}
public struct NoProofNormalizationSink : IProofNormalizationSink
{
    public static bool begin_node(uint mode, uint row, uint4 low, uint4 high) { return false; }
    public static bool set_child(uint mode, uint row, uint ordinal, uint2 reference) { return false; }
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

// Source/replacement graph view indexed by a reference's side (0 = source,
// otherwise the replacement graph). A pair over one graph shares its code for
// both sides, so the walker's single read sites inline that graph once.
public interface IProofNormalizationPair
{
    static bool node(uint side, uint row, out uint4 low, out uint4 high);
    static bool child(uint side, uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain);
    static bool constant_value(uint side, uint row, out uint3 value);
}
public struct SameProofNormalizationGraph<Graph : IProofNormalizationGraph> : IProofNormalizationPair
{
    public static bool node(uint side, uint row, out uint4 low, out uint4 high)
    { return Graph.node(row, low, high); }
    public static bool child(uint side, uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain)
    { return Graph.child(low, high, ordinal, reference, domain); }
    public static bool constant_value(uint side, uint row, out uint3 value)
    { return Graph.constant_value(row, value); }
}
public struct SplitProofNormalizationGraphs<SourceGraph : IProofNormalizationGraph,
    ReplacementGraph : IProofNormalizationGraph> : IProofNormalizationPair
{
    public static bool node(uint side, uint row, out uint4 low, out uint4 high)
    {
        if (side == 0u) return SourceGraph.node(row, low, high);
        return ReplacementGraph.node(row, low, high);
    }
    public static bool child(uint side, uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain)
    {
        if (side == 0u) return SourceGraph.child(low, high, ordinal, reference, domain);
        return ReplacementGraph.child(low, high, ordinal, reference, domain);
    }
    public static bool constant_value(uint side, uint row, out uint3 value)
    {
        if (side == 0u) return SourceGraph.constant_value(row, value);
        return ReplacementGraph.constant_value(row, value);
    }
}

// Count and emit perform the same bounded traversal and value checks. Emission
// never publishes a parent child-reference until that child's constant fitting
// has finished. Failed output remains an unpublished suffix.
// Each graph read, sink operation and count conversion has one call site:
// a visit reads its (possibly replaced) reference once, and a finished
// projection is finalized in its own iteration before its parent link, so an
// iteration performs at most one begin_node and one set_child, in the same
// order as before.
[ForceInline]
public EvidenceStatus pev_normalize_proof_root<
    Graphs : IProofNormalizationPair,
    Bindings : IProofNormalizationBindings,
    Sink : IProofNormalizationSink>(
    uint2 input, uint environment, uint visible_owner, uint domain,
    bool emit, ProofNormalizationReservation reservation,
    out uint2 normalized, out bool closed, out ProofNormalizationCounts measured)
{
    return pev_normalize_proof_root_on_side<Graphs, Bindings, Sink>(input, environment,
        visible_owner, domain, emit, reservation, 0u, normalized, closed, measured);
}
// The root is read on graph side `side`. A walk without an environment never
// substitutes, so every reference keeps that side: a pair can then select
// one of several source graphs by side (PpsAdmissionGraphs).
public EvidenceStatus pev_normalize_proof_root_on_side<
    Graphs : IProofNormalizationPair,
    Bindings : IProofNormalizationBindings,
    Sink : IProofNormalizationSink>(
    uint2 input, uint environment, uint visible_owner, uint domain,
    bool emit, ProofNormalizationReservation reservation, uint side,
    out uint2 normalized, out bool closed, out ProofNormalizationCounts measured)
{
    normalized = uint2(0u, PEV_INVALID); closed = false;
    measured = (ProofNormalizationCounts)0;
    if (domain > PEV_ADMITTED_DOMAIN_CONSTANT) return pev_invalid(4u, input.y, domain);
    if (emit && (reservation.first_node == PEV_INVALID || reservation.first_edge == PEV_INVALID ||
        reservation.node_count > PEV_INVALID - reservation.first_node ||
        reservation.edge_count > PEV_INVALID - reservation.first_edge))
        return pev_invalid(1u, input.y, PEV_INVALID);

    // The stack lives in thread scratch, six cells per depth: the reference
    // (tag, row, environment, source/replacement side), node low, node high,
    // meta (next child, child count, domain, output node), links (output
    // reference, projection child) and the value (x is a constant's declared
    // scalar even when it remains symbolic; the single child of a projection
    // supplies its value here at child completion) with its concrete flag.
    bool is_closed = true;
    uint depth = 0u;
    scratch_set_cell(SCRATCH_PEV_NORMALIZE, uint4(input.x, input.y, environment, side));
    scratch_set_cell(SCRATCH_PEV_NORMALIZE + 3u, uint4(PEV_INVALID, 0u, domain, 0u));
    [loop]
    for (;;)
    {
        uint frame = SCRATCH_PEV_NORMALIZE + depth * 6u;
        uint4 reference = scratch_cell(frame);
        uint4 node_low = scratch_cell(frame + 1u); uint4 node_high = scratch_cell(frame + 2u);
        uint4 meta = scratch_cell(frame + 3u); uint4 links = scratch_cell(frame + 4u);
        uint4 value_cell = scratch_cell(frame + 5u);
        bool begin = false; uint begin_row = 0u; uint4 begin_low = uint4(0u, 0u, 0u, 0u);
        if (meta.x == PEV_INVALID)
        {
            if (measured.visits == PEV_VISIT_LIMIT)
                return pev_limit(7u, input.y, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
            measured.visits++;
            bool constant_parameter = reference.x == 0x80000002u;
            bool substituted = false; bool replacement_constant = false;
            uint parameter = reference.y;
            if (reference.x == 2u || constant_parameter)
            {
                if (!pev_admitted_parameter_has_domain(reference.y, constant_parameter))
                    return pev_invalid(4u, input.y, reference.y);
                if (reference.z != PEV_INVALID)
                {
                    uint2 replacement;
                    if (reference.w != 0u || !Bindings.replacement(reference.z, reference.y,
                        constant_parameter, replacement)) return pev_invalid(9u, input.y, reference.y);
                    replacement_constant = replacement.x >= 0x80000001u && replacement.x <= 0x80000003u;
                    substituted = true;
                    reference = uint4(replacement.x, replacement.y, PEV_INVALID, 1u);
                }
            }
            // Pure reads of the final reference, shared by the replacement's
            // scalar check and the visit below.
            bool literal = reference.x == 0x80000001u;
            bool compound = reference.x == 3u || reference.x == 0x80000003u;
            uint3 value = uint3(0u, 0u, 0u); bool value_read = false;
            uint4 low = uint4(0u, 0u, 0u, 0u); uint4 high = low; bool node_read = false;
            if (literal) value_read = Graphs.constant_value(reference.w, reference.y, value);
            if (compound) node_read = Graphs.node(reference.w, reference.y, low, high);
            uint parameter_scalar = 0u;
            if (reference.x == 0x80000002u) parameter_scalar = pev_constant_parameter_scalar(reference.y);
            if (substituted)
            {
                // The replacement's result domain (its declared scalar).
                uint replacement_scalar = 0u;
                if (literal) replacement_scalar = value_read && constant_value_is_valid(value) ? value.x : 0u;
                else if (reference.x == 0x80000002u) replacement_scalar = parameter_scalar;
                else if (reference.x == 0x80000003u && node_read && low.x == 5u && scalar_is_integer(low.y))
                    replacement_scalar = low.y;
                if (replacement_constant != constant_parameter ||
                    (constant_parameter && replacement_scalar != pev_constant_parameter_scalar(parameter)))
                    return pev_invalid(4u, input.y, parameter);
            }
            bool constant = reference.x >= 0x80000001u && reference.x <= 0x80000003u;
            if (reference.y == PEV_INVALID ||
                (meta.z == PEV_ADMITTED_DOMAIN_TYPE && constant) ||
                (meta.z == PEV_ADMITTED_DOMAIN_CONSTANT && !constant))
                return pev_invalid(4u, input.y, reference.y);
            // next = 0, count = 0, no output node; the projection child stays
            // unset until this node's single child completes.
            meta = uint4(0u, 0u, meta.z, PEV_INVALID); links.xy = reference.xy;
            value_cell = uint4(0u, 0u, 0u, 0u);
            node_low = uint4(0u, 0u, 0u, 0u); node_high = node_low;
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
                    value_cell.x = parameter_scalar;
                    if (value_cell.x == 0u) return pev_invalid(4u, input.y, reference.y);
                }
                is_closed = false;
            }
            else if (literal)
            {
                if (!value_read || !constant_value_is_valid(value)) return pev_invalid(4u, input.y, reference.y);
                value_cell = uint4(value, 1u);
                node_low = uint4(6u, value); allocate = true;
            }
            else if (compound)
            {
                [loop]
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (all(scratch_cell(SCRATCH_PEV_NORMALIZE + ancestor * 6u) == reference))
                        return pev_invalid(5u, input.y, reference.y);
                if (!node_read || (constant ? low.x != 5u : low.x < 1u || low.x > 4u) ||
                    (low.x == 1u && (low.w > 32u || !pev_nominal_is_valid(low.y))) ||
                    (low.x == 5u && (!scalar_is_integer(low.y) || any(low.zw != uint2(0u, 0u)))))
                    return pev_invalid(4u, input.y, reference.y);
                node_low = low; node_high = high;
                meta.y = low.x == 1u ? low.w : (low.x == 2u ? 2u : 1u);
                allocate = true;
            }
            else return pev_invalid(4u, input.y, reference.y);
            if (allocate)
            {
                uint4 shape = node_low;
                uint edge_count = shape.x == 1u ? shape.w : 0u;
                if (measured.nodes == PEV_INVALID || edge_count > PEV_INVALID - measured.edges)
                    return pev_limit(64u, input.y, PEV_INVALID, PEV_INVALID - 1u);
                if (emit && (measured.nodes >= reservation.node_count ||
                    measured.edges > reservation.edge_count || edge_count > reservation.edge_count - measured.edges))
                    return pev_invalid(65u, input.y, measured.nodes);
                uint output_node = emit ? reservation.first_node + measured.nodes : measured.nodes;
                uint output_edge = emit ? reservation.first_edge + measured.edges : measured.edges;
                measured.nodes++; measured.edges += edge_count;
                meta.w = output_node;
                links.xy = uint2(constant ? reference.x : 3u, output_node);
                // A projection's row is written when it finishes.
                begin = emit && shape.x != 5u;
                begin_row = output_node;
                begin_low = shape.x == 1u ? uint4(1u, shape.y, edge_count == 0u ? 0u : output_edge, edge_count) :
                    shape.x == 6u ? shape : uint4(shape.x, shape.x == 5u ? shape.y : 0u, 0u, 0u);
            }
        }
        bool complete = meta.x == meta.y;
        uint count = 0u; bool countable = false;
        if (complete) countable = constant_value_to_count(value_cell.xyz, count);
        bool link = false; uint link_row = 0u; uint link_ordinal = 0u; uint2 link_reference = uint2(0u, 0u);
        // A pending projection retains its complete expression. A concrete
        // projection discharges both count-domain and target-range checks
        // on GPU and becomes an owned exact literal before parent publish.
        // (A visit iteration never finishes a projection: it has one child.)
        bool finalize = complete && node_low.x == 5u;
        if (finalize)
        {
            uint target = node_low.y;
            if (!scalar_is_integer(value_cell.x)) return pev_invalid(4u, input.y, reference.y);
            begin = emit; begin_row = meta.w;
            if (value_cell.w != 0u)
            {
                uint3 fitted;
                if (!countable || !constant_value_from_count(count, target, fitted))
                    return pev_invalid(66u, input.y, reference.y);
                value_cell.xyz = fitted;
                links.x = 0x80000001u;
                begin_low = uint4(6u, fitted);
            }
            else
            {
                value_cell.x = target;
                begin_low = uint4(5u, target, 0u, 0u);
                link = emit; link_row = meta.w; link_reference = links.zw;
            }
            // Finalized: the next iteration completes it in its parent.
            node_low.x = 0u;
        }
        if (begin && !Sink.begin_node(reservation.sink_mode, begin_row, begin_low, uint4(0u, 0u, 0u, 0u)))
            return pev_invalid(1u, input.y, begin_row);
        bool pop = complete && !finalize;
        if (pop)
        {
            if (depth == 0u)
            {
                if (emit && (measured.nodes != reservation.node_count || measured.edges != reservation.edge_count))
                    return pev_invalid(65u, input.y, measured.nodes);
                if (emit) normalized = links.xy;
                closed = is_closed; return pev_ok();
            }
            uint parent = frame - 6u;
            uint parent_kind = scratch_word(parent + 1u, 0u);
            uint4 parent_meta = scratch_cell(parent + 3u);
            uint ordinal = parent_meta.x - 1u;
            if (parent_kind == 5u)
            {
                scratch_set_cell(parent + 5u, value_cell);
                scratch_set_word(parent + 4u, 2u, links.x);
                scratch_set_word(parent + 4u, 3u, links.y);
            }
            if (parent_kind == 2u && ordinal == 1u)
            {
                if (!scalar_is_integer(value_cell.x)) return pev_invalid(4u, input.y, reference.y);
                if (value_cell.w != 0u && !countable)
                    return pev_invalid(66u, input.y, reference.y);
            }
            link = emit && parent_kind != 5u;
            link_row = parent_meta.w; link_ordinal = ordinal; link_reference = links.xy;
        }
        if (link && !Sink.set_child(reservation.sink_mode, link_row, link_ordinal, link_reference))
            return pev_invalid(1u, input.y, link_row);
        if (pop) { depth--; continue; }
        uint ordinal = meta.x;
        if (!complete) meta.x = ordinal + 1u;
        scratch_set_cell(frame, reference);
        scratch_set_cell(frame + 1u, node_low); scratch_set_cell(frame + 2u, node_high);
        scratch_set_cell(frame + 3u, meta); scratch_set_cell(frame + 4u, links);
        scratch_set_cell(frame + 5u, value_cell);
        if (complete) continue;
        uint2 child; uint child_domain;
        if (!Graphs.child(reference.w, node_low, node_high, ordinal, child, child_domain))
            return pev_invalid(4u, input.y, reference.y);
        if (depth + 1u == PEV_DEPTH_LIMIT) return pev_limit(6u, input.y, depth + 2u, PEV_DEPTH_LIMIT);
        depth++;
        scratch_set_cell(frame + 6u, uint4(child.x, child.y, reference.z, reference.w));
        scratch_set_cell(frame + 9u, uint4(PEV_INVALID, 0u, child_domain, 0u));
    }
}
