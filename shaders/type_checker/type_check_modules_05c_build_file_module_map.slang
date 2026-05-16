// GPU file-to-module-id table construction.
//
// Scheduling contract:
// - Dispatch after module records and module status have been produced, and
//   after type_check_modules_05b_clear_file_module_map.slang.
// - Each valid module record scatters its module id into module_id_by_file_id
//   using parser-owned HIR file ids.
// - This pass builds a GPU array table only. It does not inspect source bytes,
//   perform CPU path lookup, resolve declarations, make imports visible, use
//   hashes, or apply same-source shortcuts.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_file_id;
StructuredBuffer<uint> module_status;

RWStructuredBuffer<uint> module_id_by_file_id;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint MODULE_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint module_i = linear_thread_id(dtid);
    if (module_i >= active_module_count())
        return;
    if (module_status[module_i] != MODULE_STATUS_OK)
        return;

    uint file_id = module_file_id[module_i];
    if (file_id < gParams.module_capacity)
        module_id_by_file_id[file_id] = module_i;
}
