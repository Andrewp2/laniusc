import generated_parse_production_ids;
import hir_records;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; uint records_use_token_rows; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> semantic_prefix_before_raw;
StructuredBuffer<uint> raw_to_item;
StructuredBuffer<uint> generic_owner_by_hir;
StructuredBuffer<uint> candidate_raw_by_anchor;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<HirRange> generic_param_ranges;
RWStructuredBuffer<uint> owner_value;
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

bool valid_raw(uint raw) { return raw != INVALID && raw < gCanonical.raw_capacity; }
bool generic_decl_item_kind(uint kind)
{
    return kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN ||
           kind == HIR_ITEM_KIND_STRUCT || kind == HIR_ITEM_KIND_ENUM ||
           kind == HIR_ITEM_KIND_TYPE_ALIAS || kind == HIR_ITEM_KIND_TRAIT;
}
bool generic_decl_node(uint raw)
{
    if (!valid_raw(raw) || raw_to_hir[raw] == INVALID) return false;
    uint item_row = gCanonical.records_use_token_rows != 0u ? raw_to_item[raw] : raw;
    uint prod = node_kind[raw];
    if (prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB || prod == PROD_IMPL_FN)
        return (hir_method_signature_flags[raw] & METHOD_SIGNATURE_HAS_GENERICS) != 0u;
    return (item_row != INVALID && generic_decl_item_kind(hir_item_kind[item_row])) ||
           prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT;
}
uint generic_owner(uint raw)
{
    if (!valid_raw(raw)) return INVALID;
    // Generic-parameter productions precede their payloads in the raw
    // preorder stream. The preceding semantic row is therefore within the
    // declaration being parameterized; its propagated owner is shared by the
    // whole generic-parameter list.
    uint prefix = semantic_prefix_before_raw[raw];
    if (prefix == 0u || prefix > gCanonical.raw_capacity) return INVALID;
    uint semantic_row = prefix - 1u;
    uint owner = generic_owner_by_hir[semantic_row];
    return generic_decl_node(owner) ? owner : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint anchor = tid(dtid);
    if (anchor >= gCanonical.canonical_capacity) return;
    HirRange empty_range;
    empty_range.start = INVALID;
    empty_range.count = 0u;
    generic_param_ranges[anchor] = empty_range;
    owner_value[anchor] = INVALID;
    uint encoded = candidate_raw_by_anchor[anchor];
    uint raw = encoded == 0u ? INVALID : encoded - 1u;
    if (raw >= gCanonical.raw_capacity) {
        family_flag[anchor] = 0u;
        return;
    }
    uint owner = generic_owner(raw);
    owner_value[anchor] = owner;
    uint prod = node_kind[raw];
    uint token = hir_token_pos[raw];
    uint name = prod == PROD_ENUM_TYPE_PARAM ? token : (token == INVALID ? INVALID : token + 1u);
    bool valid_owner = owner < gCanonical.raw_capacity && raw_to_hir[owner] != INVALID;
    family_flag[anchor] = valid_owner && name == anchor ? 1u : 0u;
}
