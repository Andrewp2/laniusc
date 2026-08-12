// GPU declaration-key radix histogram.
//
// Scheduling contract:
// - The first byte consumes the compact declaration identity order directly;
//   later bytes consume the preceding stable-scatter output.
// - For each significant module-id byte, the host schedules histogram, GPU
//   bucket-prefix scan, GPU bucket-base scan, and stable scatter.
// - Exact `(module, namespace, name)` lookup is built separately. This sort
//   groups rows only by module for deterministic interface/import traversal.
// - This pass only counts radix buckets. It does not resolve imports, validate
//   duplicates, perform lookup, scan source bytes, use hashes, or apply
//   same-source shortcuts.

import gpu_index;
import radix;

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_id;
RWStructuredBuffer<uint> radix_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

uint decl_key_radix_key(uint decl_i, uint key_step)
{
    uint module_id = decl_i < active_decl_count() ? decl_module_id[decl_i] : INVALID;
    return radix_byte_key(encode_nullable_id(module_id, INVALID), key_step);
}

public struct DeclKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint ordered_row(uint order_i)
    {
        // Declaration rows are compacted in source order. Digit zero both
        // establishes that identity order and computes its histogram.
        if (gParams.key_step == 0u)
            radix_order_in[order_i] = order_i;
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return decl_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<DeclKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
