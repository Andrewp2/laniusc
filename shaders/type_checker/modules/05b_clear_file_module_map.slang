// GPU declaration-module lookup map clear.
//
// Scheduling contract:
// - Dispatch after module records exist and before
//   type_check_modules_05c_build_file_module_map.slang.
// - This pass initializes GPU-written module-id lookup buffers only.
// - A source file that declares no module is an unnamed module of its own.
//   Its id follows the module rows: the module count plus the number of such
//   files before it. No import path names it. The build pass then overwrites
//   the entry of every file that declares a module. A continuation file
//   (file_continuations.slang) starts INVALID.
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
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_file_id;
StructuredBuffer<uint4> body_specialization_inputs;

RWStructuredBuffer<uint> module_id_by_file_id;
RWStructuredBuffer<uint> decl_module_id;
RWStructuredBuffer<uint> import_module_id;
RWStructuredBuffer<uint> path_owner_module_id;

#include "file_continuations.slang"

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint record_capacity()
{
    return gParams.module_capacity;
}

uint file_capacity()
{
    return gParams.reserved == 0u ? gParams.module_capacity : gParams.reserved;
}

uint active_decl_count()
{
    return min(decl_count_out[0], record_capacity());
}

uint active_import_count()
{
    return min(import_count_out[0], record_capacity());
}

uint active_path_count()
{
    return min(path_count_out[0], record_capacity());
}

// The id of the unnamed module of `file_id`. Module rows are in source order
// and a file declares at most one module, so the rows before the lower bound
// are the files before `file_id` that declare one.
uint unnamed_module_of_file(uint file_id)
{
    if (body_continuation_count() != 0u && file_id >= body_continuation_first_file())
        return INVALID;
    uint module_count = min(module_count_out[0u], file_capacity());
    uint low = 0u;
    uint high = module_count;
    for (uint step = 0u; step < 32u && low < high; step++)
    {
        uint middle = (low + high) / 2u;
        if (module_file_id[middle] < file_id) low = middle + 1u;
        else high = middle;
    }
    if (low > file_id)
        return INVALID;
    uint id = module_count + (file_id - low);
    return id < file_capacity() ? id : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (i < file_capacity())
        module_id_by_file_id[i] = unnamed_module_of_file(i);
    if (i >= record_capacity())
        return;

    if (i < active_decl_count())
        decl_module_id[i] = INVALID;
    if (i < active_import_count())
        import_module_id[i] = INVALID;
    if (i < active_path_count())
        path_owner_module_id[i] = INVALID;
}
