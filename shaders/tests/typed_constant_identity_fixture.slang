import primitive_types;
import type_checker.concrete_type_equality;
// Synthetic storage deliberately defeats row-address identity. Results are
// production equality/hash outcomes, not a duplicate host type evaluator.
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;

public static const uint INVALID = 0xffffffffu;
static const uint ATOM = 0x80000001u;
static const uint PROJECTION = 0x80000003u;

bool atom(uint row, bool other, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    if (row == 0u || row == 1u) value = uint3(SCALAR_U32, other && row == 0u ? 4u : 3u, 0u);
    else if (row == 2u) value = uint3(SCALAR_U64, 3u, 0u);
    else if (row == 3u) value = uint3(SCALAR_U64, 3u, 1u);
    else if (row == 4u) value = uint3(SCALAR_I8, 0xffu, 0u);
    else if (row == 5u) value = uint3(SCALAR_BOOL, 1u, 0u);
    else if (row == 6u) value = uint3(SCALAR_F32, 0u, 0u);
    else if (row == 7u) value = uint3(SCALAR_F32, 0x80000000u, 0u);
    else if (row == 8u) value = uint3(SCALAR_U64, 0u, 1u);
    else if (row == 9u) value = uint3(SCALAR_U32, 256u, 0u);
    else if (row == 10u || row == 11u) value = uint3(SCALAR_F64, 0x42u, 0x7ff80000u);
    else if (row == 12u) value = uint3(SCALAR_F64, 0x43u, 0x7ff80000u);
    else return false;
    return true;
}

bool projection(uint row, out uint scalar, out uint2 child)
{
    scalar = SCALAR_U64; child = uint2(1u, 0u);
    if (row == 0u || row == 1u) return true;
    if (row == 2u) { child = uint2(2u, 0u); return true; }
    if (row == 3u) { scalar = SCALAR_U8; child = uint2(2u, 1u); return true; }
    if (row == 4u) { child = uint2(3u, 4u); return true; }
    if (row == 5u) { scalar = SCALAR_U8; child = uint2(1u, 9u); return true; }
    if (row == 6u) { child = uint2(3u, 5u); return true; }
    if (row == 7u) { child = uint2(3u, 8u); return true; }
    if (row == 8u) { child = uint2(3u, 7u); return true; }
    if (row == 9u) { child = uint2(3u, 3u); return true; }
    if (row >= 100u && row <= 162u)
    { child = row == 162u ? uint2(1u, 0u) : uint2(3u, row + 1u); return true; }
    if (row == 163u) { child = uint2(3u, 100u); return true; }
    return false;
}

uint2 operand(uint node)
{
    if (node == 0u || node == 4u) return uint2(1u, 0u);
    if (node == 1u) return uint2(1u, 1u);
    if (node == 2u || node == 5u) return uint2(1u, 2u);
    if (node == 3u) return uint2(1u, 3u);
    if (node == 6u) return uint2(1u, 4u);
    if (node == 7u) return uint2(1u, 5u);
    if (node == 8u || node == 9u) return uint2(3u, 0u);
    if (node == 10u) return uint2(3u, 2u);
    if (node == 11u) return uint2(3u, 3u);
    if (node == 12u) return uint2(3u, 4u);
    if (node == 13u) return uint2(1u, 6u);
    if (node == 14u) return uint2(1u, 7u);
    if (node == 15u) return uint2(1u, 8u);
    if (node == 16u) return uint2(3u, 5u);
    if (node == 17u) return uint2(3u, 6u);
    if (node == 18u) return uint2(3u, 7u);
    if (node == 19u) return uint2(1u, 10u);
    if (node == 20u) return uint2(1u, 11u);
    if (node == 21u) return uint2(1u, 12u);
    return uint2(0u, INVALID);
}

bool array_node(uint node)
{ return (node >= 4u && node <= 7u) || node == 9u || node == 15u; }

uint probe_metadata(uint node, uint field)
{
    if (node > 21u) return INVALID;
    bool array = array_node(node);
    uint2 value = operand(node);
    if (field == 0u) return array ? 2u : 1u;
    if (field == 1u) return array ? INVALID : 32u;
    if (field == 2u) return array ? 0u : 1u;
    if (field == 3u) return 1u;
    if (field == 4u) return SCALAR_I32;
    if (field == 5u) return array ? value.x : 0u;
    if (field == 6u) return array ? value.y : 0u;
    return INVALID;
}

bool probe_argument(uint node, uint slot, out uint tag, out uint payload)
{
    uint2 value = operand(node);
    tag = APPLICATION_CONSTANT_ARGUMENT | value.x; payload = value.y;
    return node <= 21u && !array_node(node) && slot == 0u;
}

bool binding(uint environment, uint reference, out uint kind, out uint payload)
{
    kind = 1u; payload = INVALID;
    if (environment == 0u && reference == 0u) { payload = 0u; return true; }
    if (environment == 1u && reference == 1u) { payload = 2u; return true; }
    if (environment == 3u && reference == 1u) { kind = 2u; payload = 1u; return true; }
    // Scalar mismatch must be rejected by the shared resolver.
    if (environment == 2u && reference == 0u) { payload = 2u; return true; }
    return false;
}

public struct LeftGraph : IScopedTypeGraph
{
    public static uint metadata(uint node, uint field) { return probe_metadata(node, field); }
    public static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { return probe_argument(node, slot, tag, payload); }
    [ForceInline]
    public static bool constant_value(uint row, out uint3 value) { return atom(row, false, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return reference == 0u ? SCALAR_U32 : (reference == 1u ? SCALAR_U64 : 0u); }
    [ForceInline]
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant) { return constant && reference < 2u; }
    public static uint parameter_slot(uint reference) { return INVALID; }
    public static uint constant_parameter_slot(uint reference) { return reference < 2u ? reference : INVALID; }
    public static bool environment_argument(uint env, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
    public static bool environment_constant(uint env, uint slot, out uint kind, out uint payload)
    { return binding(env, slot, kind, payload); }
    public static bool substitute_type_parameter(uint env, uint reference, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
    public static bool substitute_constant_parameter(uint env, uint reference, out uint kind, out uint payload)
    { return binding(env, reference, kind, payload); }
}
public struct RightGraph : IParameterScopedTypeGraph
{
    public static uint metadata(uint node, uint field) { return probe_metadata(node, field); }
    public static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { return probe_argument(node, slot, tag, payload); }
    public static bool constant_value(uint row, out uint3 value) { return atom(row, true, value); }
    public static uint constant_parameter_scalar(uint reference) { return LeftGraph.constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant) { return LeftGraph.parameter_is_valid(reference, constant); }
    public static bool substitute_type_parameter(uint env, uint reference, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
    public static bool substitute_constant_parameter(uint env, uint reference, out uint kind, out uint payload)
    { return binding(env, reference, kind, payload); }
}
