// GPU public declaration marking over compact namespace declaration tables.
//
// Scheduling contract:
// - Dispatch after type/value declaration namespace tables have been scattered.
// - For each compact declaration-table row, mark whether the declaration is
//   public. A following GPU prefix scan turns these flags into per-table public
//   prefixes used by import visibility counting.
// - This pass consumes declaration records only. It does not inspect source
//   bytes, token spelling, helper names, or function-body shapes.

import gpu_index;

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_value_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_value_key_to_decl_id;
StructuredBuffer<uint> decl_visibility;

RWStructuredBuffer<uint> decl_type_public_flag;
RWStructuredBuffer<uint> decl_value_public_flag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_type_decl_count()
{
    return min(decl_type_key_count_out[0], gParams.capacity);
}

uint active_value_decl_count()
{
    return min(decl_value_key_count_out[0], gParams.capacity);
}

uint public_decl_flag(uint decl_i)
{
    return decl_i < gParams.capacity && decl_visibility[decl_i] == HIR_ITEM_VIS_PUBLIC ? 1u : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint type_count = active_type_decl_count();
    uint value_count = active_value_decl_count();

    if (row < type_count)
    {
        uint decl_i = decl_type_key_to_decl_id[row];
        decl_type_public_flag[row] = public_decl_flag(decl_i);
    }

    if (row < value_count)
    {
        uint decl_i = decl_value_key_to_decl_id[row];
        decl_value_public_flag[row] = public_decl_flag(decl_i);
    }
}
