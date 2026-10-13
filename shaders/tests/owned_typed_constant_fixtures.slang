import primitive_types;
// Focused synthetic typed-constant graphs; no source parser or host evaluator.
import type_checker.owned_type_constraint_engine;
import type_checker.owned_type_constraint_contract;
RWStructuredBuffer<uint4> results;
static const uint INVALID = 0xffffffffu;
static const uint C = OWNED_CONSTRAINT_CONSTANT;

bool typed_value(uint row, out uint3 value)
{
    value = uint3(SCALAR_U64, 255u, 0u);
    if (row <= 1u) return true; // separate rows, same exact value
    if (row == 2u) value.y = 300u;
    else if (row == 3u) value.x = SCALAR_U32;
    else if (row == 4u) value.z = 1u;
    else if (row == 5u) value.x = SCALAR_U8;
    else if (row == 6u) value = uint3(SCALAR_I64, INVALID, INVALID);
    else if (row == 7u) value = uint3(SCALAR_BOOL, 1u, 0u);
    else if (row == 8u) value = uint3(SCALAR_F32, 0x3f800000u, 0u);
    else if (row == 9u) value.x = SCALAR_U16;
    else if (row == 10u) value = uint3(SCALAR_U16, 300u, 0u);
    else return false;
    return true;
}
uint typed_parameter_scalar(uint atom)
{
    if (atom == 101u) return SCALAR_U8;
    if (atom == 201u) return SCALAR_U16;
    return atom == 100u || atom == 200u || atom == 300u ? SCALAR_U64 : 0u;
}
bool typed_inventory(uint owner, bool constant, out uint count)
{
    if (owner == 30u) { count = constant ? 0u : 1u; return true; }
    count = constant && owner != 0u ? 1u : 0u;
    return owner == 0u || owner == 10u || owner == 11u || owner == 20u || owner == 21u;
}
uint typed_owned(uint owner, uint atom, bool constant, out uint index)
{
    index = INVALID;
    if (!constant)
    {
        if (atom != 400u) return OWNED_PARAMETER_INVALID;
        if (owner != 30u) return OWNED_PARAMETER_RIGID;
        index = 0u; return OWNED_PARAMETER_BINDABLE;
    }
    if (typed_parameter_scalar(atom) == 0u) return OWNED_PARAMETER_INVALID;
    uint expected = owner == 10u ? 100u : owner == 11u ? 101u :
        owner == 20u ? 200u : owner == 21u ? 201u : INVALID;
    if (atom != expected) return OWNED_PARAMETER_RIGID;
    index = 0u; return OWNED_PARAMETER_BINDABLE;
}
bool typed_projection(uint side, uint row, out uint scalar, out uint2 child)
{
    uint parameter = side == 0u ? 100u : 200u;
    scalar = SCALAR_U8; child = uint2(2u, parameter);
    if (row == 0u) return true;
    if (row == 1u) { scalar = SCALAR_U64; child = uint2(3u, 0u); }
    else if (row == 2u) scalar = SCALAR_U16;
    else if (row == 3u) scalar = SCALAR_U64;
    else if (row == 4u) { scalar = SCALAR_U32; child = uint2(3u, 0u); }
    else if (row == 5u) { scalar = SCALAR_U32; child = uint2(3u, 2u); }
    else if (row == 6u) { scalar = SCALAR_U64; child = uint2(2u, 300u); }
    else if (row == 7u) child = uint2(2u, 300u);
    else if (row == 8u) { scalar = SCALAR_U64; child = uint2(3u, 7u); }
    else if (row == 9u) { scalar = SCALAR_U64; child = uint2(3u, 13u); }
    else if (row == 10u) child = uint2(3u, 10u); // malformed cycle
    else if (row == 11u) { scalar = SCALAR_U64; child = uint2(1u, 0u); }
    else if (row == 12u) child = uint2(1u, 0u);
    else if (row == 13u) { scalar = SCALAR_U16; child = uint2(2u, 300u); }
    else return false;
    return true;
}
uint2 typed_length(uint side, uint node)
{
    uint parameter = side == 0u ? 100u : 200u;
    if (node == 0u) return uint2(2u, parameter);
    if (node == 1u) return uint2(3u, 0u);
    if (node == 2u) return uint2(3u, 3u);
    if (node == 3u) return uint2(1u, 0u);
    if (node == 4u) return uint2(1u, 2u);
    if (node == 5u) return uint2(3u, 6u);
    if (node == 6u) return uint2(2u, 300u);
    if (node == 7u) return uint2(2u, side == 0u ? 101u : 201u);
    if (node == 8u) return uint2(3u, 1u);
    if (node == 9u) return uint2(3u, 2u);
    if (node == 10u) return uint2(1u, 3u);
    if (node == 11u) return uint2(1u, 6u);
    return uint2(0u, INVALID);
}
uint typed_metadata(uint side, uint node, uint field)
{
    if (node > 11u) return INVALID;
    if (field == 0u) return 2u;
    if (field == 2u) return 0u;
    if (field == 3u) return 1u;
    if (field == 4u) return SCALAR_I32;
    if (field == 5u) return typed_length(side, node).x;
    if (field == 6u) return typed_length(side, node).y;
    return INVALID;
}
struct TypedLeftGraph : IOwnedConstraintPatternGraph
{
    static bool constant_value(uint row, out uint3 value) { return typed_value(row, value); }
    static uint constant_parameter_scalar(uint atom) { return typed_parameter_scalar(atom); }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return typed_projection(0u, row, scalar, child); }
    static bool parameter_is_valid(uint atom, bool constant)
    { return constant ? typed_parameter_scalar(atom) != 0u : atom == 400u; }
    static bool owner_parameter_count(uint owner, bool constant, out uint count)
    { return typed_inventory(owner, constant, count); }
    static uint owned_parameter(uint owner, uint atom, bool constant, out uint index)
    { return typed_owned(owner, atom, constant, index); }
    static uint metadata(uint node, uint field) { return typed_metadata(0u, node, field); }
    static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
}
struct TypedRightGraph : IOwnedConstraintPatternGraph
{
    static bool constant_value(uint row, out uint3 value) { return typed_value(row, value); }
    static uint constant_parameter_scalar(uint atom) { return typed_parameter_scalar(atom); }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return typed_projection(1u, row, scalar, child); }
    static bool parameter_is_valid(uint atom, bool constant)
    { return constant ? typed_parameter_scalar(atom) != 0u : atom == 400u; }
    static bool owner_parameter_count(uint owner, bool constant, out uint count)
    { return typed_inventory(owner, constant, count); }
    static uint owned_parameter(uint owner, uint atom, bool constant, out uint index)
    { return typed_owned(owner, atom, constant, index); }
    static uint metadata(uint node, uint field) { return typed_metadata(1u, node, field); }
    static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
}
OwnedConstraintLimits typed_limits()
{
    OwnedConstraintLimits limits = {64u, 128u, 256u, 1024u};
    return limits;
}
void typed_result(uint id, OwnedConstraintState state, uint expected, bool extra = true)
{
    results[id] = uint4(state.status.state, expected,
        state.status.state == expected && extra ? 1u : 0u, state.status.detail);
}
