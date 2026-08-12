import gpu_index;
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
StructuredBuffer<uint> decl_status;
RWStructuredBuffer<uint> decl_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint count = min(decl_count_out[0], gParams.decl_capacity);
    if (row < count && decl_status[row] == 0u)
        decl_lookup_insert(
            row, count, decl_module_id, decl_namespace, decl_name_id,
            decl_lookup_state);
}
