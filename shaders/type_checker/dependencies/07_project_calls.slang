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
StructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
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
    call_fn_index[token] = token;
    call_param_count[token] = edge_count - 1u;
    call_return_type[token] = return_type;
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
