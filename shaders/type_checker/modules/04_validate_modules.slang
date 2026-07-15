// GPU sorted module-key validation.
//
// Scheduling contract:
// - Dispatch after the module key radix sort has produced sorted_module_key_order.
// - Adjacent equal exact canonical path ids are duplicates.
// - This pass only validates module declarations. It does not resolve imports,
//   perform declaration lookup, produce visibility, or use CPU path lookup.

import sorted.runs;
import status;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_canonical_id;
StructuredBuffer<uint> module_path_id;
StructuredBuffer<uint> path_owner_token;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> module_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

static const uint MODULE_STATUS_OK = 0u;
static const uint MODULE_STATUS_DUPLICATE = 2u;

static const uint ERR_DUPLICATE_MODULE = 18u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return min(module_table_count_out[0], gParams.module_capacity);
}

uint record_capacity()
{
    return gParams.reserved == 0u ? gParams.module_capacity : gParams.reserved;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool module_keys_equal(uint left_module_i, uint right_module_i)
{
    return module_key_canonical_id[left_module_i] ==
           module_key_canonical_id[right_module_i];
}

public struct ModuleKeyEquality : ISortedRunEquality
{
    public static bool equal(uint left_item, uint right_item)
    {
        return module_keys_equal(left_item, right_item);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint module_count = active_module_count();
    if (i >= module_count)
        return;

    uint module_i;
    if (!sorted_order_item(
        i,
        module_count,
        module_count,
        sorted_module_key_order,
        module_i))
        return;

    if (module_status[module_i] != MODULE_STATUS_OK)
        return;

    uint prev_module_i;
    if (!sorted_adjacent_duplicate<ModuleKeyEquality>(
        i,
        module_count,
        module_count,
        sorted_module_key_order,
        module_i,
        prev_module_i))
        return;
    module_status[module_i] = MODULE_STATUS_DUPLICATE;
    uint path_id = module_path_id[module_i];
    uint token_i = path_id < record_capacity() ? path_owner_token[path_id] : record_capacity();
    record_error(token_i, ERR_DUPLICATE_MODULE, MODULE_STATUS_DUPLICATE);
}
