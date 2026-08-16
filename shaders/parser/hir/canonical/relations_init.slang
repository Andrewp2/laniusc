// Seeds canonical-parent, generic-owner, and predicate-subject discovery over
// one shared raw-parent link after parameter and type-argument compaction has
// released the additional payload columns.

import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; uint records_use_token_rows; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> raw_to_item;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_prefix_before_raw;
RWStructuredBuffer<uint> relation_link_a;
RWStructuredBuffer<uint> canonical_parent_a;
RWStructuredBuffer<uint> generic_owner_a;
RWStructuredBuffer<uint> predicate_subject_a;

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
bool subject_anchor(uint prod) { return prod == PROD_ENUM_TYPE_PARAM || prod == PROD_WHERE_TYPE_BOUND; }

bool generic_decl_item_kind(uint kind)
{
    return kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN ||
           kind == HIR_ITEM_KIND_STRUCT || kind == HIR_ITEM_KIND_ENUM ||
           kind == HIR_ITEM_KIND_TYPE_ALIAS || kind == HIR_ITEM_KIND_TRAIT;
}

bool generic_decl_node(uint node)
{
    if (!valid(node) || raw_to_hir[node] == INVALID) return false;
    uint item_kind_row = gCanonical.records_use_token_rows != 0u
        ? raw_to_item[node]
        : node;
    uint prod = node_kind[node];
    if (prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB || prod == PROD_IMPL_FN)
        return (hir_method_signature_flags[node] & METHOD_SIGNATURE_HAS_GENERICS) != 0u;
    return (item_kind_row != INVALID && generic_decl_item_kind(hir_item_kind[item_kind_row])) ||
           prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= gCanonical.raw_capacity) return;
    relation_link_a[node] = INVALID;
    canonical_parent_a[node] = INVALID;
    generic_owner_a[node] = INVALID;
    predicate_subject_a[node] = INVALID;
    if (!valid(node)) return;

    bool found_parent = false;
    bool found_owner = generic_decl_node(node);
    bool found_subject = subject_anchor(node_kind[node]);
    if (found_owner) generic_owner_a[node] = node;
    if (found_subject) predicate_subject_a[node] = node;

    uint ancestor = parent[node];
    uint span = max(1u, gCanonical.local_ancestor_span);
    for (uint hop = 0u; hop < span; ++hop)
    {
        if (!valid(ancestor) || ancestor == node) return;
        if (!found_parent && canonical_flag[ancestor] != 0u) {
            canonical_parent_a[node] = canonical_prefix_before_raw[ancestor];
            found_parent = true;
        }
        if (!found_owner && generic_decl_node(ancestor)) {
            generic_owner_a[node] = ancestor;
            found_owner = true;
        }
        if (!found_subject && subject_anchor(node_kind[ancestor])) {
            predicate_subject_a[node] = ancestor;
            found_subject = true;
        }
        if (found_parent && found_owner && found_subject) return;
        if (hop + 1u == span) {
            relation_link_a[node] = ancestor;
            return;
        }
        uint next = parent[ancestor];
        if (!valid(next) || next == ancestor) return;
        ancestor = next;
    }
}
