// A concrete predicate subject. The grammar gives a where-clause subject one
// name token. When no type parameter in scope has that name, the token may
// name a language scalar type (`where bool: Inner<[i32; M]>`). A nominal
// subject has no checked type node at its token, so it stays unsupported.

// The scalar type code that `token` names, or INVALID.
public uint predicate_scalar_subject_code(uint token,
    StructuredBuffer<uint> name_id_by_token,
    StructuredBuffer<uint> language_type_code_by_name_id)
{
    uint tokens; uint names; uint stride;
    name_id_by_token.GetDimensions(tokens, stride);
    language_type_code_by_name_id.GetDimensions(names, stride);
    if (token >= tokens) return 0xffffffffu;
    uint name = name_id_by_token[token];
    if (name >= names) return 0xffffffffu;
    uint code = language_type_code_by_name_id[name];
    // Codes from 4096 up (TY_STRUCT_BASE) are encoded declarations.
    return code != 0u && code < 4096u ? code : 0xffffffffu;
}
