// GPU record-to-module-id attachment.
//
// Scheduling contract:
// - Dispatch after declaration/import/path records have been scattered and
//   module_id_by_file_id has been populated by GPU module records.
// - Each record fetches the module id for its parser-owned file id.
// - This pass writes owner module-id tables only. It does not resolve
//   declarations, make imports visible, inspect source bytes, use hashes,
//   perform CPU path lookup, or apply same-source shortcuts.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_file_id;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_file_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> module_id_by_file_id;

RWStructuredBuffer<uint> decl_module_id;
RWStructuredBuffer<uint> import_module_id;
RWStructuredBuffer<uint> path_owner_module_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.module_capacity);
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.module_capacity);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.module_capacity);
}

uint owner_module_from_file(uint file_id)
{
    uint module_id = file_id < gParams.module_capacity ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.module_capacity)
        return;

    if (i < active_decl_count())
        decl_module_id[i] = owner_module_from_file(decl_module_file_id[i]);

    if (i < active_import_count())
        import_module_id[i] = owner_module_from_file(import_module_file_id[i]);

    if (i < active_path_count())
    {
        uint owner_hir = path_owner_hir[i];
        uint file_id = owner_hir < gParams.module_capacity ? hir_item_file_id[owner_hir] : INVALID;
        path_owner_module_id[i] = owner_module_from_file(file_id);
    }
}
