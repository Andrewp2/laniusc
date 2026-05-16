// Pre-resolution GPU import record scatter.
//
// Scheduling contract:
// - Dispatch after import_record_flag has an exclusive GPU prefix scan.
// - This pass scatters import records from parser-owned HIR fields and path ids.
// - It records string imports as unsupported metadata only; resolution remains
//   a later sorted-lookup pass.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_record_flag;
StructuredBuffer<uint> import_record_prefix;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> hir_item_import_target_kind;
StructuredBuffer<uint> path_record_prefix;

RWStructuredBuffer<uint> import_module_file_id;
RWStructuredBuffer<uint> import_path_id;
RWStructuredBuffer<uint> import_kind;
RWStructuredBuffer<uint> import_owner_hir;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes || import_record_flag[i] == 0u)
        return;

    uint slot = import_record_prefix[i];
    uint kind = hir_item_import_target_kind[i];
    import_module_file_id[slot] = hir_item_file_id[i];
    import_path_id[slot] = kind == HIR_ITEM_IMPORT_TARGET_PATH ? path_record_prefix[i] : INVALID;
    import_kind[slot] = kind;
    import_owner_hir[slot] = i;
}
