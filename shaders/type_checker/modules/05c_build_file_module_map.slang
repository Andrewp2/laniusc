// GPU file-to-module-id table construction.
//
// Scheduling contract:
// - Dispatch after module records and module status have been produced, and
//   after type_check_modules_05b_clear_file_module_map.slang.
// - Each real module record scatters its module id into module_id_by_file_id
//   using parser-owned HIR file ids. Module validity is reported by the module
//   validation passes; declarations still need to attach to their owning module
//   row so invalid-module diagnostics do not cascade into unrelated decl rows.
// - An instance-copy replay's continuation files (file_continuations.slang)
//   declare no module. Each maps to the module row of the template file it
//   continues, so its copies resolve names in that module with its imports.
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
StructuredBuffer<uint4> body_specialization_inputs;
RWStructuredBuffer<uint> module_id_by_file_id;

#include "file_continuations.slang"

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

uint file_capacity()
{
    return gParams.reserved == 0u ? gParams.module_capacity : gParams.reserved;
}

// The first module row declared in `file_id`, or INVALID. Module rows are in
// source order, so their file ids never decrease.
uint module_row_of_file(uint file_id, uint module_count)
{
    uint low = 0u;
    uint high = module_count;
    for (uint step = 0u; step < 32u && low < high; step++)
    {
        uint middle = (low + high) / 2u;
        if (module_file_id[middle] < file_id) low = middle + 1u;
        else high = middle;
    }
    return low < module_count && module_file_id[low] == file_id ? low : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint module_i = linear_thread_id(dtid);
    uint module_count = active_module_count();
    if (module_i >= module_count)
        return;

    uint file_id = module_file_id[module_i];
    if (file_id < file_capacity())
        module_id_by_file_id[file_id] = module_i;

    // Each continuation continues a distinct template file that declares a
    // module, so there are fewer of them than module rows. A continuation
    // whose template file declares none keeps INVALID and fails closed.
    if (module_i < body_continuation_count())
    {
        uint continuation = body_continuation_first_file() + module_i;
        if (continuation < file_capacity())
            module_id_by_file_id[continuation] =
                module_row_of_file(body_continued_file(module_i), module_count);
    }
}
