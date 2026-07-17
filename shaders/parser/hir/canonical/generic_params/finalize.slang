import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> owner_value;
StructuredBuffer<uint> raw_to_hir;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint owner = owner_value[raw];
    uint prod = node_kind[raw];
    uint token = hir_token_pos[raw];
    uint name = prod == PROD_ENUM_TYPE_PARAM ? token : (token == INVALID ? INVALID : token + 1u);
    bool valid_owner = owner < gCanonical.raw_capacity && raw_to_hir[owner] != INVALID;
    family_flag[raw] = valid_owner && name < gCanonical.canonical_capacity ? 1u : 0u;
}
