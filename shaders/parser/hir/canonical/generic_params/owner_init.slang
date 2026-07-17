import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> raw_to_hir;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> owner_link_a;
RWStructuredBuffer<uint> owner_value_a;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint node) { return node != INVALID && node < active_count(); }

bool generic_decl_item_kind(uint kind)
{
    return kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN ||
           kind == HIR_ITEM_KIND_STRUCT || kind == HIR_ITEM_KIND_ENUM ||
           kind == HIR_ITEM_KIND_TYPE_ALIAS || kind == HIR_ITEM_KIND_TRAIT;
}

bool generic_decl_node(uint node)
{
    if (!valid(node) || raw_to_hir[node] == INVALID) return false;
    uint prod = node_kind[node];
    if (prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB || prod == PROD_IMPL_FN)
        return (hir_method_signature_flags[node] & METHOD_SIGNATURE_HAS_GENERICS) != 0u;
    return generic_decl_item_kind(hir_item_kind[node]) ||
           prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT;
}

bool generic_param_candidate(uint node)
{
    uint prod = node_kind[node];
    return prod == PROD_ENUM_TYPE_PARAM || prod == PROD_ENUM_CONST_PARAM;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= gCanonical.raw_capacity) return;
    family_flag[node] = 0u;
    owner_link_a[node] = INVALID;
    owner_value_a[node] = INVALID;
    if (!valid(node)) return;
    family_flag[node] = generic_param_candidate(node) ? 1u : 0u;
    if (generic_decl_node(node))
    {
        owner_value_a[node] = node;
        return;
    }
    uint ancestor = parent[node];
    uint span = max(1u, gCanonical.local_ancestor_span);
    for (uint hop = 0u; hop < span; ++hop)
    {
        if (!valid(ancestor) || ancestor == node) return;
        if (generic_decl_node(ancestor))
        {
            owner_value_a[node] = ancestor;
            return;
        }
        if (hop + 1u == span)
        {
            owner_link_a[node] = ancestor;
            return;
        }
        uint next = parent[ancestor];
        if (!valid(next) || next == ancestor) return;
        ancestor = next;
    }
}
