import hir_records;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<HirCore> hir_core;
StructuredBuffer<HirPayload> hir_payload;
RWStructuredBuffer<uint> decl_by_name_token;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint ITEM_STRUCT = 6u;
static const uint ITEM_ENUM = 7u;
static const uint ITEM_TYPE_ALIAS = 8u;
static const uint ITEM_TRAIT = 10u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void clear(uint3 dtid: SV_DispatchThreadID)
{
    uint token = tid(dtid);
    if (token < gCanonical.canonical_capacity)
        decl_by_name_token[token] = INVALID;
}

bool type_declaration(uint item_kind)
{
    return item_kind == ITEM_STRUCT || item_kind == ITEM_ENUM ||
           item_kind == ITEM_TYPE_ALIAS || item_kind == ITEM_TRAIT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void scatter(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (row >= count)
        return;
    HirPayload payload = hir_payload[row];
    if (type_declaration(payload.a) && payload.b < gCanonical.canonical_capacity)
        decl_by_name_token[payload.b] = row;
}
