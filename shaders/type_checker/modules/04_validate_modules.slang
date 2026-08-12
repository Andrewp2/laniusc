// GPU direct module-key validation.
//
// Scheduling contract:
// - Dispatch after module construction has populated module_by_canonical_id.
// - The lowest module row owns each exact canonical path id; other rows are duplicates.
// - This pass only validates module declarations. It does not resolve imports,
//   perform declaration lookup, produce visibility, or use CPU path lookup.

import status;
import type_checker.modules.module_lookup;

struct Params
{
    uint path_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_by_canonical_id;
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
    return min(module_count_out[0], gParams.module_capacity);
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint module_count = active_module_count();
    if (i >= module_count)
        return;

    uint module_i = i;
    if (module_status[module_i] != MODULE_STATUS_OK)
        return;
    uint first = module_lookup_find(
        module_key_canonical_id[module_i],
        gParams.path_segment_capacity,
        module_by_canonical_id);
    if (first == module_i)
        return;
    module_status[module_i] = MODULE_STATUS_DUPLICATE;
    uint path_id = module_path_id[module_i];
    uint token_i = path_id < gParams.path_capacity
        ? path_owner_token[path_id]
        : gParams.path_segment_capacity;
    record_error(token_i, ERR_DUPLICATE_MODULE, MODULE_STATUS_DUPLICATE);
}
