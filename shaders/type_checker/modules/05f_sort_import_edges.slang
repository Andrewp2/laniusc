// GPU import-edge key radix histogram.
//
// Scheduling contract:
// - Dispatch after type_check_modules_05e_seed_import_edge_key_order.slang.
// - For key_step 0..7, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the fixed import-edge key from least-significant to
//   most-significant: target module id, then importing module id.
// - This pass only counts radix buckets. It does not scan source bytes, walk
//   module graphs on the CPU, use hashes, or append with atomics.

import gpu_index;
import radix;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_edge_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

static const uint IMPORT_STATUS_OK = 0u;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint import_capacity()
{
    return gParams.module_capacity;
}

uint active_import_count()
{
    return min(import_count_out[0], import_capacity());
}

bool valid_import_edge(uint import_i)
{
    return import_i < active_import_count() &&
           import_status[import_i] == IMPORT_STATUS_OK &&
           import_module_id[import_i] != INVALID &&
           import_target_module_id[import_i] != INVALID;
}

uint import_edge_field(uint import_i, uint field_i)
{
    if (!valid_import_edge(import_i))
        return 0u;
    uint value = field_i == 0u
        ? import_target_module_id[import_i]
        : import_module_id[import_i];
    return encode_nullable_id(value, INVALID);
}

uint import_edge_radix_key(uint import_i, uint key_step)
{
    uint field_i = radix_field_index(key_step, 1u);
    return radix_byte_key(import_edge_field(import_i, field_i), key_step);
}

public struct ImportEdgeRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_import_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return import_edge_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return import_edge_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<ImportEdgeRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
