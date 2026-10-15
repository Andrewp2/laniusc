import generated_parse_production_ids;
// Seed each payload type's walk to its enclosing enum variant. Every node's
// record is written to both ping-pong buffers; the walk then steps only over
// the compacted payload-chain rows.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> candidate_raw_by_anchor;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> owner_link_a;
RWStructuredBuffer<uint> owner_value_a;
RWStructuredBuffer<uint> owner_link_b;
RWStructuredBuffer<uint> owner_value_b;
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

// Productions between a payload type and its enum variant:
// enum_variant -> enum_variant_tuple -> fields_some -> (fields_more ->
// after_comma_more)*. Only these nodes and the payload types link to their
// parents, so the owner walk steps over payload chains instead of the whole
// tree.
bool payload_chain_node(uint raw)
{
    uint production = node_kind[raw];
    return production == PROD_ENUM_VARIANT_TUPLE ||
           production == PROD_ENUM_VARIANT_FIELDS_SOME ||
           production == PROD_ENUM_VARIANT_FIELDS_MORE ||
           production == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    uint link = INVALID;
    uint value = INVALID;
    if (valid(raw))
    {
        bool candidate = payload_candidate(raw);
        if (candidate)
        {
            uint anchor = hir_token_pos[raw];
            if (anchor < gCanonical.canonical_capacity)
            {
                uint ignored;
                InterlockedMax(candidate_raw_by_anchor[anchor], raw + 1u, ignored);
                InterlockedMax(family_flag[anchor], 1u, ignored);
            }
        }
        if (variant_node(raw))
        {
            value = raw;
        }
        else if (candidate || payload_chain_node(raw))
        {
            uint ancestor = parent[raw];
            if (valid(ancestor) && ancestor != raw)
            {
                if (variant_node(ancestor))
                    value = ancestor;
                else
                    link = ancestor;
            }
        }
    }
    owner_link_a[raw] = link;
    owner_value_a[raw] = value;
    owner_link_b[raw] = link;
    owner_value_b[raw] = value;
}
