// Fixture storage only. Every decision under test is made by a production
// canonical/scoped walker; malformed bindings deliberately reach that boundary.
import primitive_types;
import type_checker.scoped_type_equality;
import type_checker.dependencies.canonical_field_types;

public struct BoundaryParams
{
    public uint nodes; public uint arguments; public uint environments; public uint queries;
    public uint tokens; public uint reserved0; public uint reserved1; public uint reserved2;
};
public ConstantBuffer<BoundaryParams> boundary_params;
// Ten concrete metadata words followed by the first ordered argument.
public StructuredBuffer<uint> boundary_nodes;
public StructuredBuffer<uint> boundary_arguments;
// Two type slots, each (tag,payload). No fixture-side domain validation.
public StructuredBuffer<uint> boundary_environments;
// canonical type, environment, actual tag/payload, infer types/constants,
// leaf input tag/payload. Different entrypoints consume the relevant columns.
public StructuredBuffer<uint> boundary_queries;
public RWStructuredBuffer<uint> boundary_results;
public static const uint BOUNDARY_INVALID = 0xffffffffu;

public struct BoundaryGraph : IScopedTypeGraph
{
    static bool constant_value(uint row, out uint3 value)
    { value = uint3(SCALAR_U32, row, 0u); return row != BOUNDARY_INVALID; }
    static uint constant_parameter_scalar(uint reference)
    { return reference == 3u ? SCALAR_U32 : 0u; }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { scalar = SCALAR_U32; child = uint2(1u, 3u); return row == 0u; }
    static uint parameter_slot(uint reference)
    { return reference == 1u ? 0u : reference == 2u ? 1u : BOUNDARY_INVALID; }
    static uint constant_parameter_slot(uint reference)
    { return reference == 3u ? 0u : BOUNDARY_INVALID; }
    static bool parameter_is_valid(uint reference, bool constant)
    { return constant ? reference == 3u : reference == 1u || reference == 2u; }
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = BOUNDARY_INVALID;
        if (environment >= boundary_params.environments || slot >= 2u) return false;
        uint row = environment * 4u + slot * 2u;
        tag = boundary_environments[row]; payload = boundary_environments[row + 1u];
        return true;
    }
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = BOUNDARY_INVALID; return false; }
    static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return environment_argument(environment, parameter_slot(reference), tag, payload); }
    static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { kind = 0u; value = BOUNDARY_INVALID; return false; }
    static uint metadata(uint instance, uint field)
    {
        return instance < boundary_params.nodes && field < 10u
            ? boundary_nodes[instance * 11u + field] : BOUNDARY_INVALID;
    }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = BOUNDARY_INVALID;
        if (instance >= boundary_params.nodes) return false;
        uint start = boundary_nodes[instance * 11u + 10u];
        uint count = boundary_nodes[instance * 11u + 2u];
        if (slot >= count || start > boundary_params.arguments ||
            count > boundary_params.arguments - start) return false;
        tag = boundary_arguments[(start + slot) * 2u];
        payload = boundary_arguments[(start + slot) * 2u + 1u];
        return true;
    }
}
