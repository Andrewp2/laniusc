// Project resolved dependency declaration types into local relations. Type
// paths populate the tagged type-ref relation. Constant and unit-variant value
// paths retain compact metadata that survives replacement of the dependency
// page.

import dependency_interface;
import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_dependency_decl;
StructuredBuffer<uint> dependency_resolved_value_decl;
StructuredBuffer<uint> canonical_type_roots;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> resolved_dependency_value_metadata;

static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint MEMBER_GENERIC_TYPE = 2u;
static const uint MEMBER_GENERIC_CONST = 3u;
static const uint MEMBER_ENUM_VARIANT = 5u;
static const uint MEMBER_WORDS = 11u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint name_byte(uint byte_i)
{
    uint word = dependency_name_byte_word(byte_i >> 2u);
    return (word >> ((byte_i & 3u) * 8u)) & 0xffu;
}

bool same_variant_name(uint declaration_base, uint member_base)
{
    uint len = dependency_declaration_word(declaration_base + 4u);
    if (len == 0u || len > 64u ||
        len != dependency_member_word(member_base + 6u) ||
        dependency_declaration_word(declaration_base + 1u) !=
            dependency_member_word(member_base + 3u) ||
        dependency_declaration_word(declaration_base + 2u) !=
            dependency_member_word(member_base + 4u))
        return false;
    uint declaration_start = dependency_declaration_word(declaration_base + 3u);
    uint member_start = dependency_member_word(member_base + 5u);
    for (uint byte_i = 0u; byte_i < len; byte_i += 1u)
    {
        if (name_byte(declaration_start + byte_i) !=
            name_byte(member_start + byte_i))
            return false;
    }
    return true;
}

bool unit_variant_metadata(uint declaration_base, uint signature_root,
                           out uint enum_root, out uint ordinal)
{
    enum_root = 0xffffffffu;
    ordinal = 0xffffffffu;
    if (dependency_type_word(signature_root * TYPE_WORDS) != INTERFACE_TYPE_FUNCTION)
        return false;
    uint signature_base = signature_root * TYPE_WORDS;
    uint edge_start = dependency_type_word(signature_base + 3u);
    uint edge_count = dependency_type_word(signature_base + 4u);
    if (edge_count != 1u || edge_start >= dependency_count(5u))
        return false;
    uint return_type = dependency_type_edge_word(edge_start);
    if (return_type >= dependency_type_count())
        return false;
    enum_root = canonical_type_roots[return_type];
    if (enum_root >= dependency_type_count() ||
        dependency_type_word(enum_root * TYPE_WORDS) != INTERFACE_TYPE_DECLARATION)
        return false;

    uint parent = dependency_declaration_word(declaration_base + 10u);
    if (parent >= dependency_declaration_count())
        return false;
    uint parent_base = parent * DECL_WORDS;
    if (dependency_declaration_word(parent_base + 6u) != HIR_ITEM_KIND_ENUM)
        return false;
    uint parent_signature = dependency_declaration_word(parent_base + 7u);
    if (parent_signature >= dependency_type_count() ||
        canonical_type_roots[parent_signature] != enum_root)
        return false;
    uint start = dependency_declaration_word(parent_base + 8u);
    uint count = dependency_declaration_word(parent_base + 9u);
    if (start > dependency_member_count() ||
        count > dependency_member_count() - start)
        return false;
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint member_base = (start + offset) * MEMBER_WORDS;
        uint kind = dependency_member_word(member_base + 1u);
        // A bare value cannot infer a generic enum's type arguments here.
        if (kind == MEMBER_GENERIC_TYPE || kind == MEMBER_GENERIC_CONST)
            return false;
    }
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint member_base = (start + offset) * MEMBER_WORDS;
        if (dependency_member_word(member_base + 1u) == MEMBER_ENUM_VARIANT &&
            same_variant_name(declaration_base, member_base))
        {
            ordinal = dependency_member_word(member_base + 2u);
            return ordinal < count;
        }
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (path_i >= min(path_count_out[0u], gParams.path_capacity))
        return;
    uint path_record_kind = path_kind[path_i];
    uint declaration_i = path_record_kind == PATH_RECORD_KIND_HIR_TYPE_EXPR
        ? resolved_dependency_decl[path_i]
        : dependency_resolved_value_decl[path_i];
    uint owner_token = path_owner_token[path_i];
    if (declaration_i >= dependency_declaration_count() || owner_token >= gParams.token_capacity)
        return;
    uint declaration_base = declaration_i * DECL_WORDS;
    uint signature = dependency_declaration_word(declaration_i * DECL_WORDS + 7u);
    if (signature >= dependency_type_count())
        return;
    uint root = canonical_type_roots[signature];
    if (root >= dependency_type_count())
        return;
    uint type_base = root * TYPE_WORDS;
    uint type_kind = dependency_type_word(type_base);
    uint payload = dependency_type_word(type_base + 1u);
    if (path_kind[path_i] == PATH_RECORD_KIND_HIR_PATH_EXPR)
    {
        uint declaration_kind = dependency_declaration_word(declaration_base + 6u);
        uint value_base = path_i * 3u;
        if (declaration_kind == HIR_ITEM_KIND_ENUM_VARIANT)
        {
            uint enum_root;
            uint ordinal;
            if (unit_variant_metadata(declaration_base, root, enum_root, ordinal))
            {
                resolved_dependency_value_metadata[value_base] =
                    HIR_ITEM_KIND_ENUM_VARIANT;
                resolved_dependency_value_metadata[value_base + 1u] = enum_root;
                resolved_dependency_value_metadata[value_base + 2u] = ordinal;
                uint enum_base = enum_root * TYPE_WORDS;
                external_type_library_id[owner_token] =
                    dependency_type_word(enum_base + 1u);
                external_type_unit_id[owner_token] =
                    dependency_type_word(enum_base + 8u);
                external_type_local_index[owner_token] =
                    dependency_type_word(enum_base + 2u);
            }
            return;
        }
        if (declaration_kind != HIR_ITEM_KIND_CONST || type_kind != INTERFACE_TYPE_SCALAR)
            return;
        resolved_dependency_value_metadata[value_base] = HIR_ITEM_KIND_CONST;
        resolved_dependency_value_metadata[value_base + 1u] = payload;
        resolved_dependency_value_metadata[value_base + 2u] =
            dependency_declaration_word(declaration_base + 13u);
        return;
    }
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR)
        return;
    if (type_kind == INTERFACE_TYPE_SCALAR)
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_SCALAR;
        type_expr_ref_payload[owner_token] = payload;
        module_type_path_type[owner_token] = payload;
    }
    else
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_EXTERNAL_CANONICAL;
        type_expr_ref_payload[owner_token] = root;
        external_type_library_id[owner_token] = type_kind == 3u
            ? dependency_type_word(type_base + 1u)
            : dependency_type_library_id(root);
        external_type_unit_id[owner_token] = type_kind == 3u
            ? dependency_type_word(type_base + 8u)
            : dependency_type_unit_id(root);
        external_type_local_index[owner_token] = type_kind == 3u
            ? dependency_type_word(type_base + 2u)
            : dependency_type_local_index(root);
    }
    module_type_path_status[owner_token] = PATH_RESOLVE_STATUS_OK;
}
