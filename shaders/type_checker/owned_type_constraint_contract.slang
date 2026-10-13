// Adapters consume fully admitted, immutable, environment-free DAGs. Both
// graphs share exact nominal/parameter atoms, but NEVER share compound IDs.
// A parameter on the goal side remains rigid even if its atom equals an impl
// parameter atom. The selected graph side is part of variable identity.
import type_checker.concrete_type_equality;
import type_checker.type_constraint_structure;

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
    // Outermost first. Publication wraps the copied graph leaf/root in reverse.
    public uint target_scalars[64];
}

public struct OwnedConstantResolution
{
    public uint3 terminal;
    public uint variable;
    public uint result_scalar;
    public uint concrete;
    public uint3 value;
    public uint target_count;
    public uint target_scalars[64];
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
    // A term is (graph side, reference tag, reference payload). Terms retain
    // their namespace when followed through substitutions. No scratch terms
    // are published as proof. One-way bindings always name the rigid goal.
    // The fourth word is one optional CountProjection target on this edge.
    public uint4 bindings[128];
    // Constant domains only: left slots0..31, right slots32..63. Bit zero
    // requires the count domain; scalar-ID bits retain integer fit duties.
    public uint constant_fit_masks[64];
    public uint3 constant_parameters[64];
}

public OwnedConstraintStatus owned_constraint_result(uint state, uint detail,
    uint required = 0u, uint available = 0u)
{
    OwnedConstraintStatus result = {state, detail, required, available};
    return result;
}

public OwnedConstraintStatus owned_constraint_ok()
{ return owned_constraint_result(OWNED_CONSTRAINT_MATCHED, 0u); }

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
