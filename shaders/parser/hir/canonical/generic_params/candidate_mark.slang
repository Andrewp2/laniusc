import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> candidate_raw_by_anchor;

static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= active_count()) return;
    uint prod = node_kind[node];
    if (prod != PROD_ENUM_TYPE_PARAM && prod != PROD_ENUM_CONST_PARAM) return;
    uint token = hir_token_pos[node];
    uint anchor = prod == PROD_ENUM_TYPE_PARAM
        ? token
        : (token == INVALID ? INVALID : token + 1u);
    if (anchor < gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(candidate_raw_by_anchor[anchor], node + 1u, ignored);
    }
}
