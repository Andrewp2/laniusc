import hir_records;
import generated_parse_production_ids;
import prefix_scan;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> candidate_raw_by_anchor;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> owner_value;
StructuredBuffer<uint> raw_to_hir;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirGenericParam> hir_generic_params;
RWStructuredBuffer<HirRange> generic_param_ranges;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }

uint name_token(uint raw, uint prod)
{
    uint start = hir_token_pos[raw];
    if (prod == PROD_ENUM_TYPE_PARAM) return start;
    if (prod == PROD_ENUM_CONST_PARAM)
        return start == INVALID ? INVALID : start + 1u;
    return INVALID;
}
uint file_for_raw(uint raw)
{
    uint token = raw < gCanonical.raw_capacity ? hir_token_pos[raw] : INVALID;
    return token < gCanonical.canonical_capacity ? token_file_id[token] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint anchor = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (anchor == 0u) family_count[0u] = total;
    if (anchor >= gCanonical.canonical_capacity || family_flag[anchor] == 0u) return;
    uint encoded = candidate_raw_by_anchor[anchor];
    uint raw = encoded == 0u ? INVALID : encoded - 1u;
    if (raw >= gCanonical.raw_capacity) return;

    uint owner_raw = owner_value[raw];
    uint prod = node_kind[raw];

    uint block = anchor / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[anchor];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }

    HirGenericParam parameter;
    parameter.owner = owner_raw < gCanonical.raw_capacity ? raw_to_hir[owner_raw] : INVALID;
    parameter.name_token = name_token(raw, prod);
    parameter.kind = prod == PROD_ENUM_CONST_PARAM ? GENERIC_PARAM_KIND_CONST : GENERIC_PARAM_KIND_TYPE;
    parameter.file_id = file_for_raw(raw);
    hir_generic_params[row] = parameter;
    if (parameter.owner < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(generic_param_ranges[parameter.owner].start, row, ignored);
        InterlockedAdd(generic_param_ranges[parameter.owner].count, 1u, ignored);
    }
}
