import semantic_interface_layout;
// Exact aggregate result widths for imported calls. Free functions and
// associated methods must publish the same checked result ABI.

import dependency_interface;

static const uint RETURN_LAYOUT_INVALID = 0xffffffffu;
static const uint RETURN_LAYOUT_DECL_WORDS = 14u;
static const uint RETURN_LAYOUT_TYPE_WORDS = 9u;
static const uint RETURN_LAYOUT_MEMBER_WORDS = SEMANTIC_INTERFACE_MEMBER_WORDS;
static const uint RETURN_LAYOUT_SCALAR = 1u;
static const uint RETURN_LAYOUT_DECLARATION = 3u;
static const uint RETURN_LAYOUT_FUNCTION = 7u;
static const uint RETURN_LAYOUT_STRUCT = 6u;
static const uint RETURN_LAYOUT_ENUM = 7u;
static const uint RETURN_LAYOUT_FIELD = 4u;
static const uint RETURN_LAYOUT_VARIANT = 5u;

// Empty monomorphic structs have the existing zero-word result ABI. Prove
// emptiness from the complete declaration while its interface page is active;
// a zero projected width alone can also mean an unsupported aggregate layout.
public bool dependency_empty_struct_result(
    uint type_i, StructuredBuffer<uint> canonical_type_roots)
{
    uint total = dependency_type_count();
    if (type_i >= total) return false;
    uint root = canonical_type_roots[type_i];
    if (root >= total) return false;
    uint base = root * RETURN_LAYOUT_TYPE_WORDS;
    if (dependency_type_word(base) != RETURN_LAYOUT_DECLARATION ||
        dependency_type_word(base + 4u) != 0u)
        return false;
    uint declaration = dependency_find_declaration(
        dependency_type_word(base + 1u), dependency_type_word(base + 8u),
        dependency_type_word(base + 2u));
    if (declaration >= dependency_declaration_count()) return false;
    uint declaration_base = declaration * RETURN_LAYOUT_DECL_WORDS;
    if (dependency_declaration_word(declaration_base + 6u) != RETURN_LAYOUT_STRUCT)
        return false;
    uint start = dependency_declaration_word(declaration_base + 8u);
    uint count = dependency_declaration_word(declaration_base + 9u);
    uint members = dependency_member_count();
    if (start > members || count > members - start) return false;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
    {
        uint kind = dependency_member_word(
            (start + ordinal) * RETURN_LAYOUT_MEMBER_WORDS + 1u);
        if (kind == RETURN_LAYOUT_FIELD || kind == 2u || kind == 3u)
            return false;
    }
    return true;
}

public bool dependency_flat_payload_word_count(
    uint type_i,
    StructuredBuffer<uint> canonical_type_roots,
    out uint words)
{
    words = 0u;
    if (type_i >= dependency_type_count()) return false;
    type_i = canonical_type_roots[type_i];
    if (type_i >= dependency_type_count()) return false;
    uint base = type_i * RETURN_LAYOUT_TYPE_WORDS;
    uint kind = dependency_type_word(base);
    if (kind == RETURN_LAYOUT_SCALAR)
    {
        // `str` has a pointer/length ABI even though its interface kind is
        // scalar. Other supported concrete scalar codes occupy one word.
        uint scalar_code = dependency_type_word(base + 1u);
        if (scalar_code == 0u || scalar_code == 7u) return false;
        words = 1u;
        return true;
    }
    if (kind != RETURN_LAYOUT_DECLARATION) return false;
    uint declaration_i = dependency_find_declaration(
        dependency_type_word(base + 1u),
        dependency_type_word(base + 8u),
        dependency_type_word(base + 2u));
    if (declaration_i >= dependency_declaration_count()) return false;
    uint declaration_base = declaration_i * RETURN_LAYOUT_DECL_WORDS;
    if (dependency_declaration_word(declaration_base + 6u) != RETURN_LAYOUT_STRUCT)
        return false;
    uint start = dependency_declaration_word(declaration_base + 8u);
    uint count = dependency_declaration_word(declaration_base + 9u);
    if (start > dependency_member_count() ||
        count > dependency_member_count() - start)
        return false;
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint member_base = (start + offset) * RETURN_LAYOUT_MEMBER_WORDS;
        if (dependency_member_word(member_base + 1u) != RETURN_LAYOUT_FIELD)
            continue;
        uint field_type = dependency_member_word(member_base + 7u);
        if (field_type >= dependency_type_count()) return false;
        uint field_root = canonical_type_roots[field_type];
        if (field_root >= dependency_type_count() ||
            dependency_type_word(field_root * RETURN_LAYOUT_TYPE_WORDS) != RETURN_LAYOUT_SCALAR)
            return false;
        uint scalar_code = dependency_type_word(field_root * RETURN_LAYOUT_TYPE_WORDS + 1u);
        if (scalar_code == 0u || scalar_code == 7u) return false;
        words += 1u;
    }
    return true;
}

public uint dependency_aggregate_word_count(
    uint type_i,
    StructuredBuffer<uint> canonical_type_roots,
    StructuredBuffer<uint> declaration_field_count)
{
    if (type_i >= dependency_type_count()) return 0u;
    type_i = canonical_type_roots[type_i];
    if (type_i >= dependency_type_count()) return 0u;
    uint base = type_i * RETURN_LAYOUT_TYPE_WORDS;
    uint kind = dependency_type_word(base);
    if (kind == RETURN_LAYOUT_SCALAR) return 0u;
    uint library_id = kind == RETURN_LAYOUT_DECLARATION
        ? dependency_type_word(base + 1u)
        : dependency_type_library_id(type_i);
    uint unit_id = kind == RETURN_LAYOUT_DECLARATION
        ? dependency_type_word(base + 8u)
        : dependency_type_unit_id(type_i);
    uint local_index = kind == RETURN_LAYOUT_DECLARATION
        ? dependency_type_word(base + 2u)
        : dependency_type_local_index(type_i);
    if (library_id == RETURN_LAYOUT_INVALID || unit_id == RETURN_LAYOUT_INVALID ||
        local_index == RETURN_LAYOUT_INVALID)
        return 0u;
    uint declaration_i = dependency_find_declaration(library_id, unit_id, local_index);
    if (declaration_i >= dependency_declaration_count()) return 0u;
    uint declaration_base = declaration_i * RETURN_LAYOUT_DECL_WORDS;
    if (dependency_declaration_word(declaration_base + 6u) == RETURN_LAYOUT_ENUM)
    {
        // Enum storage includes its discriminant. Derive the maximum variant
        // width from exported constructor signatures.
        uint start = dependency_declaration_word(declaration_base + 8u);
        uint count = dependency_declaration_word(declaration_base + 9u);
        if (start > dependency_member_count() ||
            count > dependency_member_count() - start)
            return 0u;
        uint maximum_words = 1u;
        for (uint offset = 0u; offset < count; offset += 1u)
        {
            uint member_base = (start + offset) * RETURN_LAYOUT_MEMBER_WORDS;
            if (dependency_member_word(member_base + 1u) != RETURN_LAYOUT_VARIANT)
                continue;
            uint signature = dependency_member_word(member_base + 7u);
            if (signature >= dependency_type_count()) return 0u;
            uint signature_root = canonical_type_roots[signature];
            if (signature_root >= dependency_type_count()) return 0u;
            uint signature_base = signature_root * RETURN_LAYOUT_TYPE_WORDS;
            if (dependency_type_word(signature_base) != RETURN_LAYOUT_FUNCTION)
                return 0u;
            uint first_edge = dependency_type_word(signature_base + 3u);
            uint edge_count = dependency_type_word(signature_base + 4u);
            if (edge_count == 0u || first_edge > dependency_count(5u) ||
                edge_count > dependency_count(5u) - first_edge)
                return 0u;
            uint variant_words = 1u;
            for (uint argument = 0u; argument + 1u < edge_count; argument += 1u)
            {
                uint argument_type = dependency_type_edge_word(first_edge + argument);
                if (argument_type >= dependency_type_count()) return 0u;
                uint argument_root = canonical_type_roots[argument_type];
                if (argument_root >= dependency_type_count()) return 0u;
                if (dependency_type_word(argument_root * RETURN_LAYOUT_TYPE_WORDS) == 2u)
                {
                    uint slot = dependency_generic_type_slot(argument_root);
                    uint result_arg_count = dependency_type_word(base + 4u);
                    uint result_arg_start = dependency_type_word(base + 3u);
                    if (slot >= result_arg_count || result_arg_start > dependency_count(5u) ||
                        result_arg_count > dependency_count(5u) - result_arg_start)
                        return 0u;
                    argument_type = dependency_type_edge_word(result_arg_start + slot);
                }
                uint argument_words;
                if (!dependency_flat_payload_word_count(
                    argument_type, canonical_type_roots, argument_words))
                    return 0u;
                variant_words += argument_words;
            }
            maximum_words = max(maximum_words, variant_words);
        }
        return maximum_words;
    }
    return declaration_field_count[declaration_i];
}
