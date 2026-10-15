// Adapters consume fully admitted, immutable, environment-free DAGs. Both
// graphs share exact nominal/parameter atoms, but NEVER share compound IDs.
// A parameter on the goal side remains rigid even if its atom equals an impl
// parameter atom. The selected graph side is part of variable identity.
import type_checker.concrete_type_equality;
import type_checker.type_constraint_structure;
import thread_scratch;

public static const uint OWNED_CONSTRAINT_INVALID = 0xffffffffu;
public static const uint OWNED_CONSTRAINT_MATCHED = 1u;
public static const uint OWNED_CONSTRAINT_NO_MATCH = 2u;
public static const uint OWNED_CONSTRAINT_INVALID_INPUT = 3u;
public static const uint OWNED_CONSTRAINT_RESOURCE_LIMIT = 4u;
public static const uint OWNED_PARAMETER_INVALID = 0u;
public static const uint OWNED_PARAMETER_RIGID = 1u;
public static const uint OWNED_PARAMETER_BINDABLE = 2u;
public static const uint OWNED_CONSTRAINT_STACK = 64u;
public static const uint OWNED_CONSTRAINT_BINDINGS = 128u;
public static const uint OWNED_CONSTRAINT_CONSTANT = 0x80000000u;

public interface IConstraintMatchGraph : ITypeIdentityGraph
{
    static bool parameter_is_valid(uint reference, bool constant);
}

public interface IOwnedConstraintPatternGraph : IConstraintMatchGraph
{
    // Counts are the exact declared inventory, separately by domain. Return
    // false for an invalid owner; a count above32 is a ResourceLimit result.
    static bool owner_parameter_count(uint owner, bool constant, out uint count);
    // Validate the complete owned atom (binder, domain, source ordinal) and
    // exact declared membership. index is a dense domain index, NOT identity.
    // A valid atom outside this owner's own header returns RIGID, never a
    // coincident slot binding. Caller admission controls lexical visibility.
    static uint owned_parameter(uint owner, uint reference, bool constant, out uint index);
}

public struct OwnedConstraintStatus
{
    public uint state;
    // 1=adapter/input,2=domain,3=parameter inventory,4=unconstrained,
    // 5=depth,6=pair work,7=occurs work,8=substitution work,9=cyclic input.
    public uint detail;
    public uint required;
    public uint available;
}

public struct OwnedConstraintLimits
{
    public uint depth;
    public uint pair_visits;
    public uint occurs_visits;
    public uint substitution_steps;
}

public struct OwnedConstraintWork
{
    public uint pair_visits;
    public uint occurs_visits;
    public uint substitution_steps;
}

public struct OwnedConstraintBindingRequest
{
    public uint3 reference;
    public uint target_count;
    // Outermost first, in the target list at scratch cell `targets` (see
    // owned_constraint_target). Publication wraps the copied graph leaf/root
    // in reverse.
    public uint targets;
}

// Constant projection target lists live in thread scratch, four scalars per
// cell: one list per live resolution role (unify left/right, a discarded
// resolution, a binding request).
public static const uint OWNED_TARGETS_LEFT = SCRATCH_OWNED_TARGETS;
public static const uint OWNED_TARGETS_RIGHT = SCRATCH_OWNED_TARGETS + 16u;
public static const uint OWNED_TARGETS_DISCARD = SCRATCH_OWNED_TARGETS + 32u;
public static const uint OWNED_TARGETS_REQUEST = SCRATCH_OWNED_TARGETS + 48u;
[ForceInline]
public uint owned_constraint_target(uint targets, uint index)
{ return scratch_word(targets + (index >> 2u), index & 3u); }

public struct OwnedConstantResolution
{
    public uint3 terminal;
    // Declared scalar of the terminal reference itself (literal or parameter).
    public uint terminal_scalar;
    public uint variable;
    public uint result_scalar;
    public uint concrete;
    public uint3 value;
    public uint target_count;
    // Target list at scratch cell `targets`; first_target is its entry 0.
    public uint targets;
    public uint first_target;
    public uint fit_mask;
}

public struct OwnedConstraintState
{
    public OwnedConstraintStatus status;
    public OwnedConstraintLimits limits;
    public OwnedConstraintWork work;
    public uint2 owners;
    // left type,const; right type,const. Each domain has at most32 members.
    public uint4 counts;
    public uint4 bound;
    public uint4 seen;
    public uint2 node_capacities;
    public uint identity_capacity;
    // 0=one-way,1=overlap,2=standalone implementation-head admission.
    public uint overlap;
    public uint finished;
    // First thread-scratch cell of this state's frame (owned_constraint_frame).
    // The frame holds, per variable, a binding cell: a term is (graph side,
    // reference tag, reference payload). Terms retain their namespace when
    // followed through substitutions. No scratch terms are published as
    // proof. One-way bindings always name the rigid goal. The fourth word is
    // one optional CountProjection target on this edge. Then, for constant
    // domains only (left slots0..31, right slots32..63), the constant
    // parameter term with its fit mask in .w: bit zero requires the count
    // domain; scalar-ID bits retain integer fit duties.
    public uint frame;
}

// Frame 0 or 1 of the per-thread owned constraint state frames.
public uint owned_constraint_frame(uint index)
{ return SCRATCH_OWNED_STATE + index * SCRATCH_OWNED_STATE_CELLS; }
[ForceInline]
public uint4 owned_constraint_binding_cell(uint frame, uint variable)
{ return scratch_cell(frame + variable); }
[ForceInline]
public void owned_constraint_set_binding(uint frame, uint variable, uint4 binding)
{ scratch_set_cell(frame + variable, binding); }
// Constant parameter term (.xyz) and fit mask (.w) of one fit index.
[ForceInline]
public uint4 owned_constraint_constant_cell(uint frame, uint fit_index)
{ return scratch_cell(frame + OWNED_CONSTRAINT_BINDINGS + fit_index); }
[ForceInline]
public void owned_constraint_set_constant_term(uint frame, uint fit_index, uint3 term)
{
    uint cell = frame + OWNED_CONSTRAINT_BINDINGS + fit_index;
    scratch_set_cell(cell, uint4(term, scratch_word(cell, 3u)));
}
[ForceInline]
public void owned_constraint_set_fit_mask(uint frame, uint fit_index, uint mask)
{ scratch_set_word(frame + OWNED_CONSTRAINT_BINDINGS + fit_index, 3u, mask); }

// Inlined at every return site; field stores avoid a constructor call.
[ForceInline]
public OwnedConstraintStatus owned_constraint_result(uint state, uint detail,
    uint required = 0u, uint available = 0u)
{
    OwnedConstraintStatus result;
    result.state = state; result.detail = detail; result.required = required; result.available = available;
    return result;
}

public OwnedConstraintStatus owned_constraint_ok()
{ return owned_constraint_result(OWNED_CONSTRAINT_MATCHED, 0u); }

[ForceInline]
public OwnedConstraintStatus owned_constraint_invalid(uint detail)
{ return owned_constraint_result(OWNED_CONSTRAINT_INVALID_INPUT, detail); }

public OwnedConstraintStatus owned_constraint_limit(uint detail, uint used, uint available)
{
    // Saturate the explanatory count; overflowing it must not change the state.
    return owned_constraint_result(OWNED_CONSTRAINT_RESOURCE_LIMIT, detail,
        used == 0xffffffffu ? used : used + 1u, available);
}

public uint owned_constraint_mask(uint count)
{ return count == 32u ? 0xffffffffu : (count == 0u ? 0u : (1u << count) - 1u); }

// Static adapter lets the common unification engine keep the actual side
// rigid without requiring a solver graph to invent owner or slot methods.
public struct RigidConstraintGoalGraph<Graph : IConstraintMatchGraph> : IOwnedConstraintPatternGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return Graph.constant_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return Graph.constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return Graph.constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return Graph.parameter_is_valid(reference, constant); }
    public static bool owner_parameter_count(uint owner, bool constant, out uint count)
    { count = 0u; return owner == OWNED_CONSTRAINT_INVALID; }
    public static uint owned_parameter(uint owner, uint reference, bool constant, out uint index)
    {
        index = OWNED_CONSTRAINT_INVALID;
        return owner == OWNED_CONSTRAINT_INVALID && Graph.parameter_is_valid(reference, constant)
            ? OWNED_PARAMETER_RIGID : OWNED_PARAMETER_INVALID;
    }
    public static uint metadata(uint instance, uint field)
    { return Graph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return Graph.argument(instance, slot, tag, payload); }
}
