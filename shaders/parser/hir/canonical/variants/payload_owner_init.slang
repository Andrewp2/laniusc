import generated_parse_production_ids;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> owner_link_a;
RWStructuredBuffer<uint> owner_value_a;
static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint raw) { return raw != INVALID && raw < active_count(); }
bool variant_node(uint raw) { return valid(raw) && node_kind[raw] == PROD_ENUM_VARIANT; }
bool payload_candidate(uint raw)
{
    if (!valid(raw) || hir_kind[raw] != HIR_TYPE) return false;
    uint p = parent[raw];
    if (!valid(p)) return false;
    uint production = node_kind[p];
    return production == PROD_ENUM_VARIANT_FIELDS_SOME ||
           production == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    family_flag[raw] = 0u;
    owner_link_a[raw] = INVALID;
    owner_value_a[raw] = INVALID;
    if (!valid(raw)) return;
    family_flag[raw] = payload_candidate(raw) ? 1u : 0u;
    if (variant_node(raw))
    {
        owner_value_a[raw] = raw;
        return;
    }
    uint ancestor = parent[raw];
    uint span = max(1u, gCanonical.local_ancestor_span);
    for (uint hop = 0u; hop < span; ++hop)
    {
        if (!valid(ancestor) || ancestor == raw) return;
        if (variant_node(ancestor))
        {
            owner_value_a[raw] = ancestor;
            return;
        }
        if (hop + 1u == span)
        {
            owner_link_a[raw] = ancestor;
            return;
        }
        uint next = parent[ancestor];
        if (!valid(next) || next == ancestor) return;
        ancestor = next;
    }
}
