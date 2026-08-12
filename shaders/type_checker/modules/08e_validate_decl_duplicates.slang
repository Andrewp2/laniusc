// Marks every non-representative declaration with an equal exact namespace key.

import gpu_index;
import status;
import type_checker.modules.decl_lookup;

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
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_token_start;
StructuredBuffer<uint> decl_lookup_state;
RWStructuredBuffer<uint> decl_status;
RWStructuredBuffer<uint> decl_duplicate_of;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DECL_STATUS_OK = 0u;
static const uint DECL_STATUS_DUPLICATE = 1u;
static const uint ERR_BAD_HIR = 6u;

uint active_decl_count() { return min(decl_count_out[0], gParams.decl_capacity); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint declaration = linear_thread_id_2d(dtid, 65535u, 256u);
    if (declaration >= active_decl_count() || decl_status[declaration] != DECL_STATUS_OK)
        return;

    uint count = active_decl_count();
    uint module_id = decl_module_id[declaration];
    uint namespace_id = decl_namespace[declaration];
    uint name_id = decl_name_id[declaration];
    uint representative = decl_lookup_find(
        module_id, namespace_id, name_id, count,
        decl_module_id, decl_namespace, decl_name_id,
        decl_lookup_state);
    if (representative == INVALID || representative == declaration)
        return;
    decl_status[declaration] = DECL_STATUS_DUPLICATE;
    decl_duplicate_of[declaration] = representative;
    uint token = decl_token_start[declaration];
    record_min_token_error(status, token == INVALID ? 0u : token, ERR_BAD_HIR, DECL_STATUS_DUPLICATE);
}
