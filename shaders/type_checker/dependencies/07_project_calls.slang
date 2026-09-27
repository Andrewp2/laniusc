// Project already-resolved dependency call paths into the call pipeline.
// The path resolver is the sole authority for qualified and unqualified name
// lookup; this pass only translates its page-local declaration row into the
// stable library/unit/local identity retained across dependency pages.

import dependency_interface;
import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> declaration_field_count;
StructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_return_aggregate_word_count;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint MEMBER_WORDS = 10u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint MEMBER_FIELD = 4u;
static const uint MEMBER_ENUM_VARIANT = 5u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_path_count()
{
    return min(path_count_out[0u], gParams.path_capacity);
}

uint scalar_type(uint type_i)
{
    type_i = canonical_type_roots[type_i];
    uint base = type_i * TYPE_WORDS;
    return dependency_type_word(base) == INTERFACE_TYPE_SCALAR
        ? dependency_type_word(base + 1u)
        : 0u;
}

bool flat_payload_word_count(uint type_i, out uint words)
{
    words = 0u;
    if (type_i >= dependency_type_count()) return false;
    type_i = canonical_type_roots[type_i];
    if (type_i >= dependency_type_count()) return false;
    uint base = type_i * TYPE_WORDS;
    uint kind = dependency_type_word(base);
    if (kind == INTERFACE_TYPE_SCALAR)
    {
        // `str` has a pointer/length ABI even though its interface kind is
        // scalar. Other supported concrete scalar codes occupy one word.
        uint scalar_code = dependency_type_word(base + 1u);
        if (scalar_code == 0u || scalar_code == 7u) return false;
        words = 1u;
        return true;
    }
    if (kind != INTERFACE_TYPE_DECLARATION) return false;
    uint declaration_i = dependency_find_declaration(
        dependency_type_word(base + 1u),
        dependency_type_word(base + 8u),
        dependency_type_word(base + 2u));
    if (declaration_i >= dependency_declaration_count()) return false;
    uint declaration_base = declaration_i * DECL_WORDS;
    if (dependency_declaration_word(declaration_base + 6u) != HIR_ITEM_KIND_STRUCT)
        return false;
    uint start = dependency_declaration_word(declaration_base + 8u);
    uint count = dependency_declaration_word(declaration_base + 9u);
    if (start > dependency_member_count() ||
        count > dependency_member_count() - start)
        return false;
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint member_base = (start + offset) * MEMBER_WORDS;
        if (dependency_member_word(member_base + 1u) != MEMBER_FIELD)
            continue;
        uint field_type = dependency_member_word(member_base + 7u);
        if (field_type >= dependency_type_count()) return false;
        uint field_root = canonical_type_roots[field_type];
        if (field_root >= dependency_type_count() ||
            dependency_type_word(field_root * TYPE_WORDS) != INTERFACE_TYPE_SCALAR)
            return false;
        uint scalar_code = dependency_type_word(field_root * TYPE_WORDS + 1u);
        if (scalar_code == 0u || scalar_code == 7u) return false;
        words += 1u;
    }
    return true;
}

uint aggregate_word_count(uint type_i)
{
    type_i = canonical_type_roots[type_i];
    uint base = type_i * TYPE_WORDS;
    uint kind = dependency_type_word(base);
    uint library_id = kind == INTERFACE_TYPE_DECLARATION
        ? dependency_type_word(base + 1u)
        : dependency_type_library_id(type_i);
    uint unit_id = kind == INTERFACE_TYPE_DECLARATION
        ? dependency_type_word(base + 8u)
        : dependency_type_unit_id(type_i);
    uint local_index = kind == INTERFACE_TYPE_DECLARATION
        ? dependency_type_word(base + 2u)
        : dependency_type_local_index(type_i);
    if (library_id == INVALID || unit_id == INVALID || local_index == INVALID)
        return 0u;
    uint declaration_i = dependency_find_declaration(
        library_id, unit_id, local_index);
    if (declaration_i >= dependency_declaration_count())
        return 0u;
    uint declaration_base = declaration_i * DECL_WORDS;
    if (dependency_declaration_word(declaration_base + 6u) == HIR_ITEM_KIND_ENUM)
    {
        // Enum storage always includes its discriminant. MEMBER_FIELD counts
        // describe structs, not enum payloads. Derive the maximum variant
        // width from its exported constructor signature. Concrete scalars and
        // flat structs with scalar fields have exact ABI widths here.
        uint start = dependency_declaration_word(declaration_base + 8u);
        uint count = dependency_declaration_word(declaration_base + 9u);
        if (start > dependency_member_count() ||
            count > dependency_member_count() - start)
            return 0u;
        uint maximum_words = 1u;
        for (uint offset = 0u; offset < count; offset += 1u)
        {
            uint member_base = (start + offset) * MEMBER_WORDS;
            if (dependency_member_word(member_base + 1u) != MEMBER_ENUM_VARIANT)
                continue;
            uint signature = dependency_member_word(member_base + 7u);
            if (signature >= dependency_type_count()) return 0u;
            uint signature_root = canonical_type_roots[signature];
            if (signature_root >= dependency_type_count()) return 0u;
            uint signature_base = signature_root * TYPE_WORDS;
            if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION)
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
                uint argument_words;
                if (!flat_payload_word_count(argument_type, argument_words))
                    return 0u;
                variant_words += argument_words;
            }
            maximum_words = max(maximum_words, variant_words);
        }
        return maximum_words;
    }
    return declaration_field_count[declaration_i];
}

void publish_call(
    uint token,
    uint declaration_i,
    uint edge_count,
    uint return_root,
    uint return_type)
{
    if (token >= gParams.visible_capacity) return;
    call_dependency_library_id[token] =
        dependency_declaration_library_id(declaration_i);
    call_dependency_unit_id[token] =
        dependency_declaration_unit_id(declaration_i);
    call_dependency_local_index[token] =
        dependency_declaration_local_index(declaration_i);
    call_dependency_host_service[token] = dependency_declaration_word(
        declaration_i * DECL_WORDS + 12u);
    call_fn_index[token] = token;
    call_param_count[token] = edge_count - 1u;
    call_return_type[token] = return_type;
    call_return_aggregate_word_count[token] = aggregate_word_count(return_root);
    if (return_type == 0u)
    {
        decl_type_ref_tag[token] = TYPE_REF_EXTERNAL_CANONICAL;
        decl_type_ref_payload[token] = return_root;
        call_return_type_token[token] = token;
    }
    else
    {
        call_return_type_token[token] = INVALID;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint token = path_owner_token[path_i];
    uint declaration_i = dependency_find_declaration(
        resolved_dependency_library_id[path_i],
        resolved_dependency_unit_id[path_i],
        resolved_dependency_local_index[path_i]);
    if (token >= gParams.visible_capacity ||
        module_value_path_call_open[token] == INVALID ||
        declaration_i >= dependency_declaration_count())
        return;

    uint declaration_base = declaration_i * DECL_WORDS;
    uint signature_i = dependency_declaration_word(declaration_base + 7u);
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION)
        return;
    uint first_edge = dependency_type_word(signature_base + 3u);
    uint edge_count = dependency_type_word(signature_base + 4u);
    if (edge_count == 0u)
        return;

    uint return_type_i = dependency_type_edge_word(first_edge + edge_count - 1u);
    uint return_root = canonical_type_roots[return_type_i];
    uint return_type = scalar_type(return_type_i);
    publish_call(token, declaration_i, edge_count, return_root, return_type);
    uint call_token = module_value_path_call_open[token];
    if (call_token != token)
        publish_call(
            call_token, declaration_i, edge_count, return_root, return_type);
    uint segment_count = path_segment_count[path_i];
    if (segment_count > 1u)
    {
        uint leaf_row = path_segment_base[path_i] + segment_count - 1u;
        uint leaf_token = leaf_row < gParams.visible_capacity
            ? path_segment_token[leaf_row]
            : INVALID;
        if (leaf_token != token)
            publish_call(
                leaf_token, declaration_i, edge_count, return_root, return_type);
    }
}
