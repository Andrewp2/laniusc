// GPU direct-call generic claim radix stable scatter.

import gpu_index;
import radix;
import scatter;

struct Params
{
    uint claim_capacity;
    uint radix_bytes;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> call_generic_claim_order_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

groupshared uint local_radix_keys[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_claim_count()
{
    return min(call_generic_claim_count_out[0u], gParams.claim_capacity);
}

uint nullable_key(uint value)
{
    return encode_nullable_id(value, INVALID);
}

uint concrete_claim_key(uint row)
{
    return call_generic_claim_callee[row] != INVALID &&
           call_generic_claim_slot[row] != INVALID &&
           (call_generic_claim_type[row] != 0u || call_generic_claim_ref_tag[row] != 0u)
        ? 1u
        : 0u;
}

uint claim_key_field(uint row, uint field_i)
{
    if (row >= active_claim_count())
        return 0u;

    if (field_i == 0u)
        return concrete_claim_key(row);
    if (field_i == 1u)
        return nullable_key(call_generic_claim_slot[row]);
    return nullable_key(call_generic_claim_callee[row]);
}

uint claim_radix_key(uint row, uint key_step)
{
    uint bytes_per_field = clamp(gParams.radix_bytes, 1u, 4u);
    uint field_i = min(key_step / bytes_per_field, 2u);
    uint byte_i = key_step - field_i * bytes_per_field;
    return radix_byte_key(claim_key_field(row, field_i), byte_i);
}

public struct GenericClaimScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_claim_count();
    }

    public static uint inactive_value()
    {
        return INVALID;
    }

    public static uint ordered_value(uint order_i)
    {
        return call_generic_claim_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return claim_radix_key(value, key_step);
    }
}

public struct GenericClaimOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        call_generic_claim_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    stable_radix_scatter_block<
        uint,
        GenericClaimScatterSource,
        GenericClaimOrderOutSink,
        256>(
        linear_group_id(gid),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
