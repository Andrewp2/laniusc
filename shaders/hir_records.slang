/// Dense canonical HIR identity and source span.
public struct HirCore
{
    public uint kind;
    public uint parent;
    public uint token_start;
    public uint token_end;
}

/// Dense canonical HIR navigation and source-file identity.
public struct HirLinks
{
    public uint first_child;
    public uint next_sibling;
    public uint subtree_end;
    public uint file_id;
}

/// Kind-dependent canonical HIR payload.
public struct HirPayload
{
    public uint a;
    public uint b;
    public uint c;
    public uint d;
}

// Generic lookup and declaration-owned arity use one source-token domain.
// This helper is called only after the owner has been validated. Impl payload.b
// is a dense trait-bound HIR row (or absent for inherent impls), never a name.
public uint hir_generic_owner_token(HirCore core, HirPayload payload, uint token_capacity)
{
    uint token = core.kind == 35u ? core.token_start : payload.b;
    if (core.kind != 35u && token >= token_capacity) token = core.token_start;
    return token < token_capacity ? token : 0xffffffffu;
}

public struct HirRange
{
    public uint start;
    public uint count;
}

public struct HirCallArg
{
    public uint call;
    public uint value;
    public uint ordinal;
    public uint file_id;
}

public struct HirParam
{
    public uint owner;
    public uint name_token;
    public uint type_node;
    public uint ordinal;
}

public struct HirTypeArg
{
    public uint owner;
    public uint value;
    public uint ordinal;
    public uint file_id;
    public uint application_token;
}

public struct HirGenericParam
{
    public uint owner;
    public uint name_token;
    public uint kind;
    public uint file_id;
}

public struct HirPath
{
    public uint owner;
    public uint segment_start;
    public uint segment_count;
    public uint kind;
}

public struct HirPathSegment
{
    public uint path;
    public uint name_token;
    public uint ordinal;
    public uint file_id;
}

public struct HirField
{
    public uint owner;
    public uint name_token;
    public uint value;
    public uint ordinal;
}

public struct HirVariant
{
    public uint owner;
    public uint name_token;
    public uint ordinal;
    public uint file_id;
}

public struct HirVariantPayload
{
    public uint variant;
    public uint type_node;
    public uint ordinal;
    public uint file_id;
}

public struct HirMatchArm
{
    public uint owner;
    public uint pattern;
    public uint result;
    public uint ordinal;
}

public struct HirMatchPayload
{
    public uint arm;
    public uint pattern;
    public uint ordinal;
    public uint parent_pattern;
}

public struct HirArrayElement
{
    public uint array;
    public uint value;
    public uint ordinal;
    public uint file_id;
}

// An array literal (kind 24) leaves payload a to c INVALID and keeps its
// statement context in d. `[value; count]` sets a to HIR_ARRAY_REPEAT, b to
// the dense row of the count operand and c to the count's first token. Its
// value is its only element row. When that value is an integer or char
// literal 0 or `false`, a is HIR_ARRAY_REPEAT_ZERO instead: every word of
// the array is zero, so lowering needs no value stores. A `; count` after a
// later element, as in `[a, b; n]`, gives HIR_ARRAY_REPEAT_AFTER_LIST with
// c at the `;`; the checker rejects it.
public static const uint HIR_ARRAY_REPEAT = 37u;
public static const uint HIR_ARRAY_REPEAT_ZERO = 38u;
public static const uint HIR_ARRAY_REPEAT_AFTER_LIST = 39u;

public bool hir_array_is_repeat(HirCore core, HirPayload payload)
{
    return core.kind == 24u &&
        (payload.a == HIR_ARRAY_REPEAT || payload.a == HIR_ARRAY_REPEAT_ZERO ||
         payload.a == HIR_ARRAY_REPEAT_AFTER_LIST);
}

// The length of the array literal `node` with `elements` element rows: for
// `[value; count]` the count, which must be an integer literal that fits in
// u32 (0xffffffff otherwise); for any other literal its element count.
public uint hir_array_literal_length(StructuredBuffer<HirCore> core,
    StructuredBuffer<HirPayload> payload, uint hir_count, uint node, uint elements)
{
    if (node >= hir_count || !hir_array_is_repeat(core[node], payload[node]))
        return elements;
    uint count = payload[node].b;
    if (payload[node].a == HIR_ARRAY_REPEAT_AFTER_LIST ||
        count >= hir_count || core[count].kind != 23u) return 0xffffffffu;
    HirPayload literal = payload[count];
    // Form 3 is an integer literal; b and c hold its magnitude's low and
    // high words. 0xffffffff stays reserved for the failure value.
    return literal.a == 3u && literal.c == 0u && literal.b != 0xffffffffu
        ? literal.b : 0xffffffffu;
}

public struct HirString
{
    public uint node;
    public uint data_offset;
    public uint decoded_len;
    public uint file_id;
}

public struct HirMethodCore
{
    public uint node;
    public uint owner;
    public uint impl_node;
    public uint name_token;
}

public struct HirMethodSignature
{
    public uint first_param_token;
    public uint impl_receiver_type;
    public uint receiver_mode;
    public uint metadata;
}

public struct HirPredicate
{
    public uint owner;
    public uint subject;
    public uint bound;
    public uint metadata;
}

// Semantic classifications needed after the temporary parse tree is gone.
// Their values are independent of generated grammar-production numbers.
public static const uint HIR_SEMANTIC_NONE = 0u;
public static const uint HIR_SEMANTIC_TYPE_PATH = 1u;
public static const uint HIR_SEMANTIC_BOUND_PATH = 2u;
public static const uint HIR_SEMANTIC_BOUND_REFERENCE = 3u;
public static const uint HIR_SEMANTIC_BOUND_ARGUMENT_LIST = 4u;
public static const uint HIR_SEMANTIC_BOUND_ARGUMENT_TAIL = 5u;
public static const uint HIR_SEMANTIC_IMPL_TRAIT = 6u;
public static const uint HIR_SEMANTIC_IMPL_INHERENT = 7u;
public static const uint HIR_SEMANTIC_IMPL_FUNCTION = 8u;
public static const uint HIR_SEMANTIC_TRAIT_METHOD = 9u;
public static const uint HIR_SEMANTIC_PUBLIC_TRAIT_METHOD = 10u;
public static const uint HIR_SEMANTIC_PUBLIC_IMPL = 11u;
public static const uint HIR_SEMANTIC_TYPE_PARAM_BOUND_LIST = 12u;

/// Additional semantic links that are not part of the universal HIR record.
/// Parser production identities never cross this boundary.
public struct HirSemanticFacts
{
    public uint semantic_kind;
    public uint type_path_leaf;
    public uint method_impl_receiver_type;
    public uint expr_result_root;
    public uint struct_lit_head;
    public uint predicate_owner;
    public uint predicate_subject;
    // Float literal decode status: binary32 in bits 0..7, binary64 in bits 8..15.
    // Zero is success. This is separate from all candidate value bit patterns.
    public uint literal_status;
}
