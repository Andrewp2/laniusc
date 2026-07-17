import generated_parse_production_ids;
import prefix_scan;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirGenericParam { uint owner; uint name_token; uint kind; uint file_id; };
struct HirRange { uint start; uint count; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;
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
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }

uint name_token(uint raw, uint prod)
{
    uint start = hir_token_pos[raw];
    if (prod == PROD_ENUM_TYPE_PARAM) return start;
    if (prod == PROD_ENUM_CONST_PARAM)
        return start == INVALID ? INVALID : start + 1u;
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;

    uint owner_raw = owner_value[raw];
    uint prod = node_kind[raw];

    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
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
    parameter.file_id = hir_token_file_id[raw];
    hir_generic_params[row] = parameter;
    if (parameter.owner < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(generic_param_ranges[parameter.owner].start, row, ignored);
        InterlockedAdd(generic_param_ranges[parameter.owner].count, 1u, ignored);
    }
}
