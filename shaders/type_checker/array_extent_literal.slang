// An array type's integer literal extent that u32 cannot represent. That
// literal owns the range diagnostic (LNC0069), as in any other u32 context:
// the array length checks (conditions/compact_types and
// semantic/artifact/01b) report it there instead of an invalid or
// unsupported array.
import primitive_types;
import hir_records;
import constant_value;
import type_checker.argument_context;

static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;

// The literal's token when type row `node` is an array whose length operand
// is an integer literal (or its negation) outside u32; else 0xffffffff.
public uint array_extent_range_literal(uint node, uint count,
    StructuredBuffer<HirCore> core, StructuredBuffer<HirPayload> payload)
{
    if (node >= count || core[node].kind != HIR_TYPE || payload[node].a != HIR_TYPE_FORM_ARRAY)
        return 0xffffffffu;
    uint literal; bool negative;
    if (!integer_literal_magnitude(payload[node].d, count, core, payload, literal, negative))
        return 0xffffffffu;
    HirPayload magnitude = payload[literal];
    uint3 value;
    return constant_value_from_integer_magnitude(SCALAR_U32, uint2(magnitude.b, magnitude.c),
        negative, value) ? 0xffffffffu : core[literal].token_start;
}
