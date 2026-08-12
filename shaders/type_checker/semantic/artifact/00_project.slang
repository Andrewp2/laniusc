import hir_records;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};


ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<int> if_depth;
StructuredBuffer<uint> compact_expr_scalar_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> semantic_value_decl_by_hir;
RWStructuredBuffer<uint> semantic_value_type_by_hir;
RWStructuredBuffer<uint> semantic_value_const_by_hir;
RWStructuredBuffer<uint> semantic_value_const_present_by_hir;
RWStructuredBuffer<uint> semantic_param_type_by_row;
RWStructuredBuffer<uint> semantic_enclosing_fn_by_hir;
RWStructuredBuffer<uint> semantic_function_return_type_by_hir;
RWStructuredBuffer<uint> semantic_function_entrypoint_by_hir;
RWStructuredBuffer<uint> semantic_function_host_service_by_hir;
RWStructuredBuffer<uint> semantic_control_depth_by_hir;
RWStructuredBuffer<uint> semantic_expr_scalar_type_by_hir;
RWStructuredBuffer<uint> semantic_type_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_type_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_type_generic_param_slot_by_hir;
RWStructuredBuffer<uint> semantic_type_external_library_id_by_hir;
RWStructuredBuffer<uint> semantic_type_external_unit_id_by_hir;
RWStructuredBuffer<uint> semantic_type_external_local_index_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_EXPR_NAME = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HOST_SERVICE_FIRST = 20u;
static const uint HOST_SERVICE_END = 63u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 19u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint CONST_PRESENT = 0x80000000u;

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool token_is_wildcard(uint token)
{
    return valid_token(token) && name_id_by_token[token] != INVALID &&
        name_id_by_token[token] == language_name_id[LANGUAGE_SYMBOL_WILDCARD];
}

uint type_leaf_token(uint row, HirCore core, HirPayload payload)
{
    uint path_count = min(compact_path_count[0u], gParams.n_hir_nodes);
    uint path = row < gParams.n_hir_nodes ? path_id_by_owner_hir[row] : INVALID;
    if (path >= path_count)
        path = payload.b < gParams.n_hir_nodes ? path_id_by_owner_hir[payload.b] : INVALID;
    if (path >= path_count)
        return core.token_start;
    HirPath record = compact_paths[path];
    uint segment_count = min(compact_path_segment_count[0u], gParams.n_tokens);
    if (record.segment_count == 0u || record.segment_start >= segment_count ||
        record.segment_count > segment_count - record.segment_start)
        return core.token_start;
    return compact_path_segments[record.segment_start + record.segment_count - 1u].name_token;
}

uint host_service_for_function(HirPayload payload)
{
    if (payload.a != HIR_ITEM_KIND_EXTERN_FN || !valid_token(payload.b)) return INVALID;
    uint name_id = name_id_by_token[payload.b];
    for (uint service = HOST_SERVICE_FIRST; service < HOST_SERVICE_END; ++service)
    {
        if (service == LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR) continue;
        if (language_name_id[service] == name_id) return service;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row < gParams.n_hir_nodes)
    {
        uint declaration = INVALID;
        uint type_id = 0u;
        uint const_value = 0u;
        uint const_present = 0u;
        if (row < hir_count)
        {
            HirCore core = compact_hir_core[row];
            HirPayload payload = compact_hir_payload[row];
            if ((core.kind == HIR_NAME_EXPR || payload.a == HIR_EXPR_NAME) &&
                valid_token(payload.d))
            {
                declaration = visible_decl[payload.d];
                type_id = visible_type[payload.d];
                if (token_is_wildcard(core.token_start))
                {
                    declaration = core.token_start;
                    type_id = 0u;
                }
            }
            else if ((core.kind == HIR_LET_STMT ||
                      (core.kind == HIR_STMT &&
                       (payload.a == HIR_STMT_LET || payload.a == HIR_STMT_CONST))) &&
                     valid_token(payload.b))
            {
                declaration = payload.b;
                type_id = visible_type[payload.b];
            }
            else if (core.kind == HIR_CONST_ITEM && valid_token(payload.b))
            {
                declaration = payload.b;
                type_id = visible_type[payload.b];
            }
            if (core.kind == HIR_PATH_EXPR)
            {
                uint path = path_id_by_owner_hir[row];
                if (path != INVALID && path < gParams.n_hir_nodes)
                {
                    uint value_base = path * 3u;
                    if (resolved_dependency_value_metadata[value_base] == HIR_ITEM_KIND_CONST)
                    {
                        type_id = resolved_dependency_value_metadata[value_base + 1u];
                        const_value = resolved_dependency_value_metadata[value_base + 2u];
                        const_present = CONST_PRESENT;
                    }
                }
            }
        }
        semantic_value_decl_by_hir[row] = declaration;
        semantic_value_type_by_hir[row] = type_id;
        semantic_value_const_by_hir[row] = const_value;
        semantic_value_const_present_by_hir[row] = const_present;
        uint token = row < hir_count ? compact_hir_core[row].token_start : INVALID;
        uint nearest_fn = row < hir_count ? compact_hir_nearest_fn[row] : INVALID;
        semantic_enclosing_fn_by_hir[row] = nearest_fn < hir_count ? nearest_fn + 1u : 0u;
        semantic_function_return_type_by_hir[row] = valid_token(token) ? call_return_type[token] : 0u;
        semantic_function_entrypoint_by_hir[row] = valid_token(token) ? fn_entrypoint_tag[token] : 0u;
        semantic_function_host_service_by_hir[row] = row < hir_count
            ? host_service_for_function(compact_hir_payload[row]) : INVALID;
        semantic_control_depth_by_hir[row] = valid_token(token)
            ? uint(max(if_depth[token], 0)) : 0u;
            semantic_expr_scalar_type_by_hir[row] = row < hir_count
            ? compact_expr_scalar_type[row] : 0u;

        uint type_tag = INVALID;
        uint type_payload = INVALID;
        uint external_library = INVALID;
        uint external_unit = INVALID;
        uint external_local = INVALID;
        uint generic_param_slot = INVALID;
        if (row < hir_count && compact_hir_core[row].kind == HIR_TYPE)
        {
            HirCore core = compact_hir_core[row];
            HirPayload payload = compact_hir_payload[row];
            uint leaf = type_leaf_token(row, core, payload);
            uint head = core.token_start;
            uint identity_token = valid_token(leaf) ? leaf : head;
            if (valid_token(identity_token))
            {
                type_tag = type_expr_ref_tag[identity_token];
                type_payload = type_expr_ref_payload[identity_token];
            }
            if ((type_tag == INVALID || type_tag == 0u) && valid_token(head))
            {
                type_tag = type_expr_ref_tag[head];
                type_payload = type_expr_ref_payload[head];
            }
            if (type_tag == 2u)
            {
                uint parameter_token = valid_token(type_payload) ? type_payload : identity_token;
                if (valid_token(parameter_token))
                    generic_param_slot = type_generic_param_slot_by_token[parameter_token];
            }
            uint external_token = valid_token(identity_token) &&
                external_type_library_id[identity_token] != INVALID
                ? identity_token : INVALID;
            if (external_token == INVALID && valid_token(type_payload) &&
                external_type_library_id[type_payload] != INVALID)
                external_token = type_payload;
            if (external_token == INVALID && valid_token(head) &&
                external_type_library_id[head] != INVALID)
                external_token = head;
            if (external_token != INVALID)
            {
                external_library = external_type_library_id[external_token];
                external_unit = external_type_unit_id[external_token];
                external_local = external_type_local_index[external_token];
            }
        }
        semantic_type_ref_tag_by_hir[row] = type_tag;
        semantic_type_ref_payload_by_hir[row] = type_payload;
        semantic_type_generic_param_slot_by_hir[row] = generic_param_slot;
        semantic_type_external_library_id_by_hir[row] = external_library;
        semantic_type_external_unit_id_by_hir[row] = external_unit;
        semantic_type_external_local_index_by_hir[row] = external_local;

    }

    uint param_count = min(compact_param_count[0u], gParams.n_hir_nodes);
    if (row < gParams.n_hir_nodes)
    {
        uint type_id = 0u;
        if (row < param_count)
        {
            uint token = compact_params[row].name_token;
            if (valid_token(token)) type_id = visible_type[token];
        }
        semantic_param_type_by_row[row] = type_id;
    }
}
