// GPU sorted module-key validation.
//
// Scheduling contract:
// - Dispatch after the module key radix sort has produced sorted_module_key_order.
// - Adjacent equal module path keys are duplicates; equality compares full
//   segment-name-id rows, not hashes.
// - This pass only validates module declarations. It does not resolve imports,
//   perform declaration lookup, produce visibility, or use CPU path lookup.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> module_path_id;
StructuredBuffer<uint> path_owner_token;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> module_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;

static const uint MODULE_STATUS_OK = 0u;
static const uint MODULE_STATUS_DUPLICATE = 2u;

static const uint ERR_BAD_HIR = 6u;

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
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool module_keys_equal(uint left_module_i, uint right_module_i)
{
    uint left_count = min(module_key_segment_count[left_module_i], MAX_PATH_SEGMENTS);
    uint right_count = min(module_key_segment_count[right_module_i], MAX_PATH_SEGMENTS);
    if (left_count != right_count)
        return false;

    uint left_base = module_key_segment_base[left_module_i];
    uint right_base = module_key_segment_base[right_module_i];
    [loop]
    for (uint segment_i = 0u; segment_i < left_count; segment_i += 1u)
    {
        if (module_key_segment_name_id[left_base + segment_i] !=
            module_key_segment_name_id[right_base + segment_i])
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint module_count = active_module_count();
    if (i >= module_count)
        return;

    uint module_i = sorted_module_key_order[i];
    if (module_i >= module_count)
        return;

    if (module_status[module_i] != MODULE_STATUS_OK)
        return;
    if (i == 0u)
        return;

    uint prev_module_i = sorted_module_key_order[i - 1u];
    if (prev_module_i >= module_count)
        return;

    if (!module_keys_equal(prev_module_i, module_i))
        return;

    module_status[module_i] = MODULE_STATUS_DUPLICATE;
    uint path_id = module_path_id[module_i];
    uint token_i = path_id < gParams.module_capacity ? path_owner_token[path_id] : gParams.module_capacity;
    record_error(token_i, ERR_BAD_HIR, MODULE_STATUS_DUPLICATE);
}
