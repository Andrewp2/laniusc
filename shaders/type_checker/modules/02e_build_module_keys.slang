// Builds exact module keys from canonical path-prefix ids.
//
// Prefix ids are produced by the parallel doubling/interner stage. The hash
// table used there only places exact pairs; therefore one canonical id denotes
// one complete segment sequence without a path-depth bound or hash ambiguity.

import gpu_index;
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
StructuredBuffer<uint> path_prefix_id;
StructuredBuffer<uint> path_owner_token;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> module_status;
RWStructuredBuffer<uint> module_key_canonical_id;
RWStructuredBuffer<uint> module_key_segment_count;
RWStructuredBuffer<uint> module_key_segment_base;
RWStructuredBuffer<uint> module_key_to_module_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MODULE_STATUS_OK = 0u;
static const uint MODULE_STATUS_EMPTY_PATH = 1u;
static const uint MODULE_STATUS_INACTIVE = 4u;
static const uint ERR_INVALID_MODULE_PATH = 20u;

uint active_module_count()
{
    return min(module_table_count_out[0u], gParams.module_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint module_i = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    if (module_i >= active_module_count())
        return;

    uint owner_hir = module_owner_hir[module_i];
    uint path_id = module_path_id[module_i];
    bool active = owner_hir != INVALID && path_id < gParams.record_capacity;
    uint count = active ? path_segment_count[path_id] : 0u;
    uint base = active ? path_segment_base[path_id] : 0u;

    module_key_segment_count[module_i] = count;
    module_key_segment_base[module_i] = base;
    module_key_to_module_id[module_i] = module_i;
    module_key_canonical_id[module_i] = count == 0u
        ? INVALID
        : path_prefix_id[base + count - 1u];

    if (!active)
    {
        module_status[module_i] = MODULE_STATUS_INACTIVE;
        return;
    }
    if (count == 0u)
    {
        module_status[module_i] = MODULE_STATUS_EMPTY_PATH;
        record_min_token_error(
            status,
            path_owner_token[path_id],
            ERR_INVALID_MODULE_PATH,
            MODULE_STATUS_EMPTY_PATH);
        return;
    }
    module_status[module_i] = MODULE_STATUS_OK;
}
