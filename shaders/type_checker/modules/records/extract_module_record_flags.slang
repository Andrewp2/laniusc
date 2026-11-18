// GPU module/path record-family flag projection.
//
// Scheduling contract:
// - Dispatch after type_check_modules_00_mark_records.slang has produced packed
//   HIR-indexed record_family_bits.
// - This pass projects exactly one record-family bit into a reusable u32 flag
//   buffer for the existing GPU prefix-scan/compact-scatter pipeline.
// - It does not inspect tokens, source bytes, names, path segments, or helper
//   shapes; classification was already recorded as HIR metadata bits.

struct Params
{
    uint n_hir_nodes;
    uint family_bit;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> record_family_bits;
RWStructuredBuffer<uint> record_family_flag;

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
    if (i >= gParams.n_hir_nodes)
        return;

    record_family_flag[i] =
        (record_family_bits[i] & gParams.family_bit) != 0u ? 1u : 0u;
}
