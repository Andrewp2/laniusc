// GPU declaration-module lookup map clear.
//
// Scheduling contract:
// - Dispatch before type_check_modules_05c_build_file_module_map.slang.
// - This pass initializes GPU-written module-id lookup buffers only.
// - It does not inspect source bytes, perform CPU path lookup, resolve
//   declarations, make imports visible, use hashes, or apply same-source
//   shortcuts.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> path_count_out;

RWStructuredBuffer<uint> module_id_by_file_id;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.module_capacity)
        return;

    module_id_by_file_id[i] = INVALID;
    if (i < active_decl_count())
        decl_module_id[i] = INVALID;
    if (i < active_import_count())
        import_module_id[i] = INVALID;
    if (i < active_path_count())
        path_owner_module_id[i] = INVALID;
}
