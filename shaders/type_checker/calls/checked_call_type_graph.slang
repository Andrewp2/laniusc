import type_checker.constant_atoms;
import type_checker.calls.checked_constant_environment;
// Complete checked call types for validators that only read accepted facts.
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;
import type_checker.calls.checked_call_environment;
import type_checker.calls.contextual_call_environment;

// Constraint inference reads argument claims only. Its output table must not
// become its own input when the inference loop revisits the same call.
public struct ScopedCheckedArgumentTypeGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<ScopedCheckedArgumentTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<ScopedCheckedArgumentTypeGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<ScopedCheckedArgumentTypeGraph>(environment, reference, kind, value); }
    public static uint constant_parameter_slot(uint token) { return ScopedCheckedTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    {
        if ((environment & 0x80000000u) == 0u) return ScopedCheckedTypeGraph.environment_constant(environment, slot, kind, value);
        return checked_argument_environment_constant_ref(environment, slot, kind, value);
    }
    public static uint parameter_slot(uint token)
    { return ScopedCheckedTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field)
    { return ScopedCheckedTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        if ((environment & 0x80000000u) == 0u)
            return ScopedCheckedTypeGraph.environment_argument(environment, slot, tag, payload);
        return checked_call_environment_argument(environment, slot, tag, payload);
    }
}

public struct ScopedCheckedCallTypeGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<ScopedCheckedCallTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<ScopedCheckedCallTypeGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<ScopedCheckedCallTypeGraph>(environment, reference, kind, value); }
    public static uint constant_parameter_slot(uint token) { return ScopedCheckedTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    {
        if ((environment & 0x80000000u) == 0u) return ScopedCheckedTypeGraph.environment_constant(environment, slot, kind, value);
        return checked_call_environment_constant_ref(environment, slot, kind, value);
    }
    public static uint parameter_slot(uint token)
    { return ScopedCheckedTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field)
    { return ScopedCheckedTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        if ((environment & 0x80000000u) == 0u)
            return ScopedCheckedTypeGraph.environment_argument(environment, slot, tag, payload);
        return checked_call_environment_argument(environment, slot, tag, payload) ||
            checked_context_environment_argument(environment, slot, tag, payload);
    }
}

// Derive both result domains independently of provisional argument facts.
// Repeated parameters must agree in the complete declared result pattern.
public struct ScopedDeclaredResultTypeGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<ScopedDeclaredResultTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<ScopedDeclaredResultTypeGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<ScopedDeclaredResultTypeGraph>(environment, reference, kind, value); }
    public static uint constant_parameter_slot(uint token) { return ScopedCheckedArgumentTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = 0xffffffffu; return false; }
    public static uint parameter_slot(uint token) { return ScopedCheckedTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field) { return ScopedCheckedTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = 0xffffffffu; return false; }
}
