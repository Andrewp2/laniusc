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
public bool bind_explicit_constant_operand<TypeRefs : IExplicitOperandTypeRefs>(
    TypeRefs type_refs, uint argument_row, uint expected_scalar)
{
    return bind_scoped_explicit_constant_operand(type_refs, ModuleScopeOperandNames(),
        argument_row, expected_scalar);
}

public bool bind_scoped_explicit_constant_operand<TypeRefs : IExplicitOperandTypeRefs,
    BodyNames : IExplicitOperandBodyNames>(
    TypeRefs type_refs, BodyNames body_names, uint argument_row, uint expected_scalar)
{
    uint kind; uint payload;
    if (!checked_scoped_explicit_constant_operand(type_refs, body_names,
        explicit_mapping_arguments[argument_row].value, expected_scalar, kind, payload)) return false;
    uint operand = explicit_mapping_arguments[argument_row].value;
    call_explicit_arg_constant_kind[operand] = kind;
    call_explicit_arg_constant_payload[operand] = payload;
    return true;
}

// An application whose binder already recorded one operand's own diagnostic
// (an out-of-range literal). It is rejected; its validators add nothing.
public static const uint EXPLICIT_APPLICATION_OPERAND_DIAGNOSED = 5u;

// The literal token of an operand that failed to bind only because its
// integer literal does not fit the declared integer scalar.
public bool explicit_constant_operand_out_of_range(uint argument_row, uint expected_scalar,
    out uint literal_token)
{
    return explicit_integer_literal_out_of_range(explicit_mapping_arguments[argument_row].value,
        expected_scalar, literal_token);
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
