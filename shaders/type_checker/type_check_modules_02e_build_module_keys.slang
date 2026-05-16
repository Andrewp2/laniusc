// Pre-resolution GPU module key construction.
//
// Scheduling contract:
// - Dispatch after module records and path segment records have been scattered.
// - This pass copies each module declaration path's interned segment ids into a
//   fixed-width key row that a later GPU radix sort can order.
// - It does not sort keys, resolve imports, perform declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_path_id;
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
static const uint MAX_PATH_SEGMENTS = 64u;

static const uint MODULE_STATUS_OK = 0u;
static const uint MODULE_STATUS_EMPTY_PATH = 1u;
static const uint MODULE_STATUS_PATH_TOO_DEEP = 3u;

static const uint ERR_BAD_HIR = 6u;
static const uint SORT_PATH_SEGMENTS = 8u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.n_hir_nodes);
}

uint valid_path_id(uint path_id)
{
    return path_id < gParams.n_hir_nodes ? path_id : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint module_i = i / MAX_PATH_SEGMENTS;
    uint segment_i = i - module_i * MAX_PATH_SEGMENTS;
    if (module_i >= active_module_count())
        return;

    uint path_id = valid_path_id(module_path_id[module_i]);
    uint count = path_id == INVALID ? 0u : min(path_segment_count[path_id], MAX_PATH_SEGMENTS);
    uint key_base = module_i * MAX_PATH_SEGMENTS;
    uint dst = key_base + segment_i;

    if (segment_i == 0u)
    {
        module_key_segment_count[module_i] = count;
        module_key_segment_base[module_i] = key_base;
        module_key_to_module_id[module_i] = module_i;
        module_status[module_i] = count == 0u ? MODULE_STATUS_EMPTY_PATH : MODULE_STATUS_OK;
        if (count == 0u)
        {
            uint token_i = path_id == INVALID ? gParams.n_tokens : path_owner_token[path_id];
            record_error(token_i, ERR_BAD_HIR, MODULE_STATUS_EMPTY_PATH);
        }
        else if (count > SORT_PATH_SEGMENTS)
        {
            module_status[module_i] = MODULE_STATUS_PATH_TOO_DEEP;
            uint token_i = path_id == INVALID ? gParams.n_tokens : path_owner_token[path_id];
            record_error(token_i, ERR_BAD_HIR, MODULE_STATUS_PATH_TOO_DEEP);
        }
    }

    if (segment_i >= count)
    {
        module_key_segment_name_id[dst] = INVALID;
        return;
    }

    uint src = path_segment_base[path_id] + segment_i;
    module_key_segment_name_id[dst] = path_segment_name_id[src];
}
