// The expected type of each struct-literal field in caller scope, as a
// canonical ID. A field's declaration-side reference and the literal's
// application (struct_init_field_expected_ref_* and
// struct_init_field_expected_context_instance, written by
// 04_struct_init_fields) are substituted once by 01_field_expected_ids, which
// also gives the result a checked row (ct_row_of), so readers need neither a
// scoped hash walk nor a substitution of their own.
//
// struct_init_field_expected_ct[field token] is the ID while the field has a
// context instance, CT_NONE while it has none (its reference is already in
// caller scope) and CT_UNKNOWN when the substitution failed.
import type_checker.canonical.canonical_api;

public RWStructuredBuffer<uint> struct_init_field_expected_ct;

public uint ct_field_expected(uint token)
{
    uint count; uint stride;
    struct_init_field_expected_ct.GetDimensions(count, stride);
    return token < count ? struct_init_field_expected_ct[token] : CT_UNKNOWN;
}
