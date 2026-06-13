// GPU declaration namespace table marking.
//
// Scheduling contract:
// - Dispatch after declaration-key radix sort and duplicate validation.
// - The input order is the sorted declaration-key table. This pass marks valid
//   type/value declarations by namespace so GPU prefix scans can allocate
//   compact lookup tables without source scans or token-local semantic logic.
// - It does not resolve imports, expand visibility, resolve type/value paths,
//   read source bytes, or apply same-source shortcuts.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> sorted_decl_key_order;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_status;

RWStructuredBuffer<uint> decl_type_key_flag;
RWStructuredBuffer<uint> decl_value_key_flag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint DECL_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.decl_capacity)
        return;

    decl_type_key_flag[i] = 0u;
    decl_value_key_flag[i] = 0u;

    if (i >= active_decl_count())
        return;

    uint decl_i = sorted_decl_key_order[i];
    if (decl_i >= active_decl_count() || decl_status[decl_i] != DECL_STATUS_OK)
        return;

    uint namespace = decl_namespace[decl_i];
    if (namespace == HIR_ITEM_NAMESPACE_TYPE)
        decl_type_key_flag[i] = 1u;
    else if (namespace == HIR_ITEM_NAMESPACE_VALUE)
        decl_value_key_flag[i] = 1u;
}
