import hir_records;
import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; uint records_use_token_rows; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_to_raw;
StructuredBuffer<uint> type_root_owner;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> raw_to_item;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> subject_anchor;
RWStructuredBuffer<uint> owner_value;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
bool valid_raw(uint raw) { return raw != INVALID && raw < gCanonical.raw_capacity; }
bool valid_dense(uint dense) { return dense != INVALID && dense < gCanonical.canonical_capacity; }
bool bound_type(uint prod) { return prod == PROD_BOUND_TYPE_IDENT || prod == PROD_BOUND_TYPE_REF; }

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
uint nearest_generic_owner(uint raw)
{
    uint ancestor = raw;
    for (uint hop = 0u; hop < gCanonical.raw_capacity; ++hop)
    {
        if (!valid_raw(ancestor)) return INVALID;
        if (generic_decl_node(ancestor)) return ancestor;
        uint next = parent[ancestor];
        if (next == ancestor) return INVALID;
        ancestor = next;
    }
    return INVALID;
}
bool subject_node(uint raw)
{
    uint prod = valid_raw(raw) ? node_kind[raw] : INVALID;
    return prod == PROD_ENUM_TYPE_PARAM || prod == PROD_WHERE_TYPE_BOUND;
}
uint nearest_subject(uint raw)
{
    uint ancestor = raw;
    for (uint hop = 0u; hop < gCanonical.raw_capacity; ++hop)
    {
        if (!valid_raw(ancestor)) return INVALID;
        if (subject_node(ancestor)) return ancestor;
        uint next = parent[ancestor];
        if (next == ancestor) return INVALID;
        ancestor = next;
    }
    return INVALID;
}

bool direct_generic_bound(uint raw, uint anchor)
{
    if (!bound_type(node_kind[raw])) return false;
    uint dense = raw_to_hir[raw];
    if (!valid_dense(dense) || hir_to_raw[dense] != raw || !valid_raw(anchor)) return false;
    uint anchor_prod = node_kind[anchor];
    if (anchor_prod != PROD_ENUM_TYPE_PARAM && anchor_prod != PROD_WHERE_TYPE_BOUND) return false;
    // Bound-path forwarding wrappers can be published as the raw type-argument
    // owner even though they canonicalize to the same semantic type. Only a
    // distinct dense owner means this bound is nested argument syntax rather
    // than the predicate root itself.
    // Type-root ownership is the canonical, pointer-jumped relation. Raw
    // type-argument owners may still name grammar forwarding wrappers, which
    // can incorrectly classify a predicate root as its own nested argument.
    uint raw_root = type_root_owner[raw];
    uint dense_root = valid_raw(raw_root) ? raw_to_hir[raw_root] : INVALID;
    return dense_root == INVALID || dense_root == dense;
}

bool trait_impl_bound(uint raw)
{
    uint owner = valid_raw(raw) ? parent[raw] : INVALID;
    uint target = valid_raw(raw) ? next_sibling[raw] : INVALID;
    return node_kind[raw] == PROD_TYPE_IDENT && valid_raw(owner) &&
           node_kind[owner] == PROD_IMPL_TRAIT && valid_raw(target) &&
           parent[target] == owner && node_kind[target] == PROD_TYPE_IDENT &&
           valid_dense(raw_to_hir[raw]) && valid_dense(raw_to_hir[target]) &&
           valid_dense(raw_to_hir[owner]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = tid(dtid);
    if (dense >= gCanonical.canonical_capacity) return;
    subject_anchor[dense] = INVALID;
    owner_value[dense] = INVALID;
    uint raw = dense < min(canonical_count[0u], gCanonical.canonical_capacity)
        ? canonical_dense_to_raw[dense]
        : INVALID;
    bool bound_candidate = valid_raw(raw) && bound_type(node_kind[raw]);
    uint anchor = bound_candidate ? nearest_subject(raw) : INVALID;
    bool direct_bound = bound_candidate && direct_generic_bound(raw, anchor);
    bool impl_bound = valid_raw(raw) && trait_impl_bound(raw);
    uint owner = direct_bound ? nearest_generic_owner(raw) : INVALID;
    subject_anchor[dense] = anchor;
    owner_value[dense] = owner;
    family_flag[dense] = direct_bound || impl_bound ? 1u : 0u;
}
