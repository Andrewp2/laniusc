// Project resolved dependency declaration types into local relations. Type
// paths populate the tagged type-ref relation. Constant value paths retain a
// compact `(kind, scalar type, value)` record that remains valid after the
// reusable dependency page is replaced.

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
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
        if (dependency_declaration_word(declaration_base + 6u) != HIR_ITEM_KIND_CONST ||
            type_kind != INTERFACE_TYPE_SCALAR)
            return;
        uint value_base = path_i * 3u;
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
