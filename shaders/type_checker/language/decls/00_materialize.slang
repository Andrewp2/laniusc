struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> language_decl_symbol_slot;
StructuredBuffer<uint> language_decl_kind;
StructuredBuffer<uint> language_decl_tag;

RWStructuredBuffer<uint> language_decl_name_id;
RWStructuredBuffer<uint> language_type_code_by_name_id;
RWStructuredBuffer<uint> language_entrypoint_tag_by_name_id;
RWStructuredBuffer<uint> language_intrinsic_tag_by_name_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint LANGUAGE_NAME_COUNT = 19u;
static const uint LANGUAGE_SYMBOL_COUNT = 20u;
static const uint LANGUAGE_DECL_COUNT = 19u;
static const uint LANGUAGE_DECL_KIND_ENTRYPOINT = 1u;
static const uint LANGUAGE_DECL_KIND_INTRINSIC = 2u;
static const uint LANGUAGE_DECL_KIND_PRIMITIVE_TYPE = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= LANGUAGE_DECL_COUNT)
        return;

    uint symbol_slot = language_decl_symbol_slot[i];
    uint kind = language_decl_kind[i];
    uint tag = language_decl_tag[i];
    uint name_id = kind != 0u && tag != 0u && symbol_slot < LANGUAGE_NAME_COUNT
                       ? language_name_id[symbol_slot]
                       : INVALID;
    language_decl_name_id[i] = name_id;
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;
    if (kind == LANGUAGE_DECL_KIND_ENTRYPOINT)
        language_entrypoint_tag_by_name_id[name_id] = tag;
    if (kind == LANGUAGE_DECL_KIND_INTRINSIC)
        language_intrinsic_tag_by_name_id[name_id] = tag;
    if (kind == LANGUAGE_DECL_KIND_PRIMITIVE_TYPE && name_id != INVALID &&
        name_id < gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        language_type_code_by_name_id[name_id] = tag;
}
