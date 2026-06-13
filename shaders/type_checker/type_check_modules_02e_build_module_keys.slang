// Pre-resolution GPU module key construction.
//
// Scheduling contract:
// - Dispatch after module records and path segment records have been scattered.
// - This pass copies each module declaration path's interned segment ids into a
//   fixed-width key row that a later GPU radix sort can order.
// - It does not sort keys, resolve imports, perform declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import status;

struct Params
{
    uint record_capacity;
    uint module_capacity;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> module_path_id;
StructuredBuffer<uint> module_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> module_status;
RWStructuredBuffer<uint> module_key_segment_count;
RWStructuredBuffer<uint> module_key_segment_base;
RWStructuredBuffer<uint> module_key_segment_name_id;
RWStructuredBuffer<uint> module_key_to_module_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MODULE_STATUS_OK = 0u;
static const uint MODULE_STATUS_EMPTY_PATH = 1u;
static const uint MODULE_STATUS_PATH_TOO_DEEP = 3u;
static const uint MODULE_STATUS_INACTIVE = 4u;

static const uint ERR_MODULE_PATH_TOO_DEEP = 19u;
static const uint ERR_INVALID_MODULE_PATH = 20u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return min(module_table_count_out[0], gParams.module_capacity);
}

uint valid_path_id(uint path_id)
{
    return path_id < gParams.record_capacity ? path_id : INVALID;
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
    uint module_i = i / MODULE_KEY_SEGMENT_ROW_WIDTH;
    uint segment_i = i - module_i * MODULE_KEY_SEGMENT_ROW_WIDTH;
    if (module_i >= active_module_count())
        return;

    uint key_base = module_i * MODULE_KEY_SEGMENT_ROW_WIDTH;
    uint dst = key_base + segment_i;
    uint owner_hir = module_owner_hir[module_i];
    uint path_id = owner_hir == INVALID ? INVALID : valid_path_id(module_path_id[module_i]);

    if (owner_hir == INVALID)
    {
        if (segment_i == 0u)
        {
            module_key_segment_count[module_i] = 0u;
            module_key_segment_base[module_i] = key_base;
            module_key_to_module_id[module_i] = module_i;
            module_status[module_i] = MODULE_STATUS_INACTIVE;
        }
        module_key_segment_name_id[dst] = INVALID;
        return;
    }

    uint count = path_id == INVALID ? 0u : path_segment_count[path_id];

    if (segment_i == 0u)
    {
        module_key_segment_count[module_i] = count;
        module_key_segment_base[module_i] = key_base;
        module_key_to_module_id[module_i] = module_i;
        module_status[module_i] = count == 0u ? MODULE_STATUS_EMPTY_PATH : MODULE_STATUS_OK;
        if (count == 0u)
        {
            uint token_i = path_id == INVALID ? gParams.record_capacity : path_owner_token[path_id];
            record_error(token_i, ERR_INVALID_MODULE_PATH, MODULE_STATUS_EMPTY_PATH);
        }
        else if (count > SORT_PATH_SEGMENTS)
        {
            module_status[module_i] = MODULE_STATUS_PATH_TOO_DEEP;
            uint token_i = path_id == INVALID ? gParams.record_capacity : path_owner_token[path_id];
            record_error(token_i, ERR_MODULE_PATH_TOO_DEEP, MODULE_STATUS_PATH_TOO_DEEP);
        }
    }

    if (segment_i >= min(count, MODULE_KEY_SEGMENT_ROW_WIDTH))
    {
        module_key_segment_name_id[dst] = INVALID;
        return;
    }

    uint src = path_segment_base[path_id] + segment_i;
    module_key_segment_name_id[dst] = path_segment_name_id[src];
}
