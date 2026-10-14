import type_checker.constant_atoms;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.mutable_checked_type_graph;
import type_checker.scoped_type_equality;
import type_checker.calls.checked_call_environment;
import type_checker.calls.contextual_call_environment;

// These producers materialize under call bindings. Receiver field expansion
// has its own nominal environment reader in MutableCheckedTypeGraph. A low-bit
// instance ID must never be admitted as a call environment here.
public struct MutableCheckedCallTypeGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    [ForceInline]
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<MutableCheckedCallTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<MutableCheckedCallTypeGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<MutableCheckedCallTypeGraph>(environment, reference, kind, value); }
    [ForceInline]
    public static uint constant_parameter_slot(uint token) { return MutableCheckedTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    {
        return checked_call_environment_constant_ref(environment, slot, kind, value);
    }
    public static uint parameter_slot(uint token)
    { return MutableCheckedTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field)
    { return MutableCheckedTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return MutableCheckedTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        return checked_call_environment_argument(environment, slot, tag, payload) ||
            checked_context_environment_argument(environment, slot, tag, payload);
    }
}

// Expected parameter patterns use the declared result constraint before a
// provisional argument binding. Actual value materialization keeps the graph
// above; strict claim validation compares the two after inference closes.
public struct MutableCheckedExpectedCallTypeGraph<TPriority : ICheckedCallClaimPriority> : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<MutableCheckedExpectedCallTypeGraph<TPriority>>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<MutableCheckedExpectedCallTypeGraph<TPriority>>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<MutableCheckedExpectedCallTypeGraph<TPriority>>(environment, reference, kind, value); }
    public static uint constant_parameter_slot(uint token) { return MutableCheckedCallTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return MutableCheckedCallTypeGraph.environment_constant(environment, slot, kind, value); }
    public static uint parameter_slot(uint token) { return MutableCheckedCallTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field) { return MutableCheckedCallTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return MutableCheckedCallTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        return checked_explicit_environment_argument(environment, slot, tag, payload) ||
            checked_context_environment_argument(environment, slot, tag, payload) ||
            prioritized_checked_call_environment_argument<TPriority>(environment, slot, tag, payload);
    }
}
