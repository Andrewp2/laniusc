// Pre-resolution GPU module record scatter.
//
// Scheduling contract:
// - Dispatch after module_record_flag has an exclusive GPU prefix scan.
// - This pass scatters module declaration records from parser-owned HIR fields.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_record_flag;
StructuredBuffer<uint> module_record_prefix;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> path_record_prefix;

RWStructuredBuffer<uint> module_file_id;
RWStructuredBuffer<uint> module_path_id;
RWStructuredBuffer<uint> module_owner_hir;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes || module_record_flag[i] == 0u)
        return;

    uint slot = module_record_prefix[i];
    module_file_id[slot] = hir_item_file_id[i];
    module_path_id[slot] = path_record_prefix[i];
    module_owner_hir[slot] = i;
}
