import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> type_arg_owner;
StructuredBuffer<uint> subject_anchor;
StructuredBuffer<HirCore> hir_core;
RWStructuredBuffer<uint> family_flag;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
bool valid_raw(uint raw) { return raw != INVALID && raw < gCanonical.raw_capacity; }
bool valid_dense(uint dense) { return dense != INVALID && dense < gCanonical.canonical_capacity; }
bool bound_type(uint prod) { return prod == PROD_BOUND_TYPE_IDENT || prod == PROD_BOUND_TYPE_REF; }

bool direct_generic_bound(uint raw)
{
    if (!bound_type(node_kind[raw])) return false;
    uint dense = raw_to_hir[raw];
    uint anchor = subject_anchor[raw];
    if (canonical_flag[raw] == 0u || !valid_dense(dense) || !valid_raw(anchor)) return false;
    uint anchor_prod = node_kind[anchor];
    if (anchor_prod != PROD_ENUM_TYPE_PARAM && anchor_prod != PROD_WHERE_TYPE_BOUND) return false;
    return type_arg_owner[raw] == INVALID;
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
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    family_flag[raw] = direct_generic_bound(raw) || trait_impl_bound(raw) ? 1u : 0u;
}
