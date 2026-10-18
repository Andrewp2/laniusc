// A compact application row owns its lexical slot. Only a completed declaration
// match publishes status 1; consumers never read partly initialized mappings.
import hir_records;
import type_checker.calls.explicit_constant_operand;
public RWStructuredBuffer<uint> call_explicit_application_status;
public RWStructuredBuffer<uint> call_explicit_arg_slot;
public RWStructuredBuffer<uint> call_explicit_arg_constant_kind;
public RWStructuredBuffer<uint> call_explicit_arg_constant_payload;
StructuredBuffer<uint> explicit_mapping_argument_count;
StructuredBuffer<HirTypeArg> explicit_mapping_arguments;
StructuredBuffer<HirRange> explicit_mapping_argument_ranges;

// A binding slot is tagged by domain. Type and constant slot zero can coexist.
public static const uint EXPLICIT_CONSTANT_SLOT = 0x80000000u;
// Binds one explicit constant operand; the result is its
// EXPLICIT_OPERAND_* reason (explicit_constant_operand).
public uint bind_scoped_explicit_constant_operand<TypeRefs : IExplicitOperandTypeRefs,
    BodyNames : IExplicitOperandBodyNames>(
    TypeRefs type_refs, BodyNames body_names, uint argument_row, uint expected_scalar)
{
    uint kind; uint payload;
    uint operand = explicit_mapping_arguments[argument_row].value;
    uint reason = checked_scoped_explicit_constant_operand(type_refs, body_names, operand,
        expected_scalar, kind, payload);
    if (reason != EXPLICIT_OPERAND_BOUND) return reason;
    call_explicit_arg_constant_kind[operand] = kind;
    call_explicit_arg_constant_payload[operand] = payload;
    return EXPLICIT_OPERAND_BOUND;
}

// The application status after operand `ordinal` failed for `reason`. An
// operand diagnosed at itself is 5 | reason << 4 | ordinal << 8 | scalar << 16
// (the final application check reports it); any other failure is 3.
public uint explicit_operand_failure_status(uint reason, uint ordinal, uint scalar)
{
    bool diagnosed = reason == EXPLICIT_OPERAND_LITERAL_RANGE ||
        reason == EXPLICIT_OPERAND_SCALAR_CONFLICT;
    return diagnosed ? 5u | (reason << 4u) | (ordinal << 8u) | (scalar << 16u) : 3u;
}

public bool explicit_application_range(uint token, out HirRange arguments)
{
    arguments.start = 0xffffffffu; arguments.count = 0u;
    uint capacity; uint stride;
    call_explicit_application_status.GetDimensions(capacity, stride);
    if (token >= capacity) return false;
    arguments = explicit_mapping_argument_ranges[token];
    if (arguments.count == 0u) return false;
    uint count = explicit_mapping_argument_count[0u];
    if (arguments.count > 64u || arguments.start > count || arguments.count > count - arguments.start)
    { call_explicit_application_status[token] = 4u; return false; }
    for (uint i = 0u; i < arguments.count; i++)
    {
        HirTypeArg row = explicit_mapping_arguments[arguments.start + i];
        if (row.application_token != token || row.ordinal != i)
        { call_explicit_application_status[token] = 4u; return false; }
    }
    return true;
}
