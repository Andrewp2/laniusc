import hir_records;

// Resolve a bare nominal reference only through the completed native-layout
// producer's identity rows. The legacy struct and enum code ranges overlap;
// an ambiguous code has no usable declaration or layout.
public uint native_nominal_token(uint scalar, uint token_capacity,
    StructuredBuffer<uint> native_scalar_identity)
{
    static const uint INVALID = 0xffffffffu;
    uint record = scalar >= 4096u ? scalar - 4096u : INVALID;
    uint enumeration = scalar >= 6144u ? scalar - 6144u : INVALID;
    bool record_matches = record < token_capacity && native_scalar_identity[record] == scalar;
    bool enum_matches = enumeration < token_capacity && native_scalar_identity[enumeration] == scalar;
    if (record_matches == enum_matches) return INVALID;
    return record_matches ? record : enumeration;
}

// Layout producers resolve the same identity from immutable declaration rows.
// Native consumers with declaration layouts use this relation as well.
public uint native_nominal_declaration_token(uint scalar, uint token_capacity,
    uint hir_count, StructuredBuffer<uint> declaration_hir,
    StructuredBuffer<HirCore> cores)
{
    static const uint INVALID = 0xffffffffu;
    uint record = scalar >= 4096u ? scalar - 4096u : INVALID;
    uint enumeration = scalar >= 6144u ? scalar - 6144u : INVALID;
    uint record_hir = record < token_capacity ? declaration_hir[record] : INVALID;
    uint enum_hir = enumeration < token_capacity ? declaration_hir[enumeration] : INVALID;
    bool record_matches = record_hir < hir_count && cores[record_hir].kind == 27u;
    bool enum_matches = enum_hir < hir_count && cores[enum_hir].kind == 26u;
    if (record_matches == enum_matches) return INVALID;
    return record_matches ? record : enumeration;
}
