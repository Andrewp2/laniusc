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
static const uint HIR_ITEM = 2u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void clear(uint3 dtid: SV_DispatchThreadID)
{
    uint token = tid(dtid);
    if (token < gCanonical.canonical_capacity)
        decl_by_name_token[token] = INVALID;
}

bool type_declaration(uint hir_kind, uint item_kind)
{
    return (hir_kind == HIR_STRUCT_ITEM && item_kind == ITEM_STRUCT) ||
           (hir_kind == HIR_ENUM_ITEM && item_kind == ITEM_ENUM) ||
           (hir_kind == HIR_TYPE_ALIAS_ITEM && item_kind == ITEM_TYPE_ALIAS) ||
           (hir_kind == HIR_ITEM && item_kind == ITEM_TRAIT);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void scatter(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (row >= count)
        return;
    HirCore core = hir_core[row];
    HirPayload payload = hir_payload[row];
    if (type_declaration(core.kind, payload.a) &&
        payload.b < gCanonical.canonical_capacity)
        decl_by_name_token[payload.b] = row;
}
