// Resolve each HIR type node to the local declaration row selected by the
// module resolver. Named generic instances use their checked instance binding
// as a fallback; neither path inspects source spelling.

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_id_by_name_token;
RWStructuredBuffer<uint> interface_type_local_decl_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
bool valid_token(uint token) { return token < gParams.token_capacity; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    uint local = INVALID;
    uint path = path_id_by_owner_hir[node];
    if (path < gParams.hir_capacity && resolved_type_decl[path] < gParams.decl_capacity)
        local = resolved_type_decl[path];
    uint token = hir_token_pos[node];
    if (local == INVALID && valid_token(token) && type_expr_ref_tag[token] == TYPE_REF_INSTANCE)
    {
        uint instance = type_expr_ref_payload[token];
        uint decl_token = valid_token(instance) ? type_instance_decl_token[instance] : INVALID;
        uint instance_local = valid_token(decl_token) ? decl_id_by_name_token[decl_token] : INVALID;
        if (instance_local < gParams.decl_capacity)
            local = instance_local;
    }
    interface_type_local_decl_by_hir[node] = local;
}
