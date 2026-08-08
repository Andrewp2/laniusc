import hir_records;

// Resolve each HIR type node to the local declaration row selected by the
// module resolver. Named generic instances use their checked instance binding
// as a fallback; neither path inspects source spelling.

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_id_by_name_token;
RWStructuredBuffer<uint> interface_type_local_decl_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
bool valid_token(uint token) { return token < gParams.token_capacity; }
uint path_leaf_token(uint node)
{
    uint path_count = min(compact_path_count[0u], gParams.hir_capacity);
    uint path = node < gParams.hir_capacity ? path_id_by_owner_hir[node] : INVALID;
    if (path >= path_count)
    {
        uint path_owner = node < gParams.hir_capacity ? compact_hir_payload[node].b : INVALID;
        path = path_owner < gParams.hir_capacity ? path_id_by_owner_hir[path_owner] : INVALID;
    }
    if (path >= path_count)
        return INVALID;
    HirPath record = compact_paths[path];
    uint segment_count = min(compact_path_segment_count[0u], gParams.token_capacity);
    if (record.segment_count == 0u || record.segment_start >= segment_count ||
        record.segment_count > segment_count - record.segment_start)
        return INVALID;
    return compact_path_segments[record.segment_start + record.segment_count - 1u].name_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    uint local = INVALID;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (node >= active) { interface_type_local_decl_by_hir[node] = INVALID; return; }
    uint token = compact_hir_core[node].token_start;
    uint path = valid_token(token) ? path_id_by_owner_token[token] : INVALID;
    if (path < gParams.hir_capacity && resolved_type_decl[path] < gParams.decl_capacity)
        local = resolved_type_decl[path];
    if (local == INVALID && valid_token(token) && type_expr_ref_tag[token] == TYPE_REF_INSTANCE)
    {
        uint instance = type_expr_ref_payload[token];
        uint decl_token = valid_token(instance) ? type_instance_decl_token[instance] : INVALID;
        uint instance_local = valid_token(decl_token) ? decl_id_by_name_token[decl_token] : INVALID;
        if (instance_local < gParams.decl_capacity)
            local = instance_local;
    }
    uint leaf_token = path_leaf_token(node);
    if (local == INVALID && valid_token(leaf_token))
    {
        uint leaf_path = path_id_by_owner_token[leaf_token];
        if (leaf_path < gParams.hir_capacity && resolved_type_decl[leaf_path] < gParams.decl_capacity)
            local = resolved_type_decl[leaf_path];
        if (local == INVALID && type_expr_ref_tag[leaf_token] == TYPE_REF_INSTANCE)
        {
            uint instance = type_expr_ref_payload[leaf_token];
            uint decl_token = valid_token(instance) ? type_instance_decl_token[instance] : INVALID;
            uint instance_local = valid_token(decl_token) ? decl_id_by_name_token[decl_token] : INVALID;
            if (instance_local < gParams.decl_capacity)
                local = instance_local;
        }
    }
    interface_type_local_decl_by_hir[node] = local;
}
