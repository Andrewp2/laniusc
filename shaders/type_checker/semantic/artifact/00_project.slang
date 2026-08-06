import hir_records;
import gpu_index;
import dependency_interface;

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
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<int> if_depth;
StructuredBuffer<uint> compact_expr_scalar_type;
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

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_EXPR_NAME = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HOST_SERVICE_FIRST = 20u;
static const uint HOST_SERVICE_END = 63u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint DECL_WORDS = 14u;

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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
                if (path != INVALID &&
                    resolved_dependency_library_id[path] != INVALID &&
                    resolved_dependency_unit_id[path] != INVALID &&
                    resolved_dependency_local_index[path] != INVALID)
                {
                    uint dependency_decl = dependency_find_declaration(
                        resolved_dependency_library_id[path],
                        resolved_dependency_unit_id[path],
                        resolved_dependency_local_index[path]);
                    if (dependency_decl != INVALID &&
                        dependency_declaration_word(dependency_decl * DECL_WORDS + 6u) ==
                            HIR_ITEM_KIND_CONST)
                    {
                        const_value = dependency_declaration_word(
                            dependency_decl * DECL_WORDS + 13u);
                        const_present = 1u;
                    }
                }
            }
        }
        semantic_value_decl_by_hir[row] = declaration;
        semantic_value_type_by_hir[row] = type_id;
        semantic_value_const_by_hir[row] = const_value;
        semantic_value_const_present_by_hir[row] = const_present;
        uint token = row < hir_count ? compact_hir_core[row].token_start : INVALID;
        semantic_enclosing_fn_by_hir[row] = valid_token(token) ? enclosing_fn[token] : 0u;
        semantic_function_return_type_by_hir[row] = valid_token(token) ? call_return_type[token] : 0u;
        semantic_function_entrypoint_by_hir[row] = valid_token(token) ? fn_entrypoint_tag[token] : 0u;
        semantic_function_host_service_by_hir[row] = row < hir_count
            ? host_service_for_function(compact_hir_payload[row]) : INVALID;
        semantic_control_depth_by_hir[row] = valid_token(token)
            ? uint(max(if_depth[token], 0)) : 0u;
        semantic_expr_scalar_type_by_hir[row] = row < hir_count
            ? compact_expr_scalar_type[row] : 0u;

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
