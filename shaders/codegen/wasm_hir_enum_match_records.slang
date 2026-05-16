// Pack parser-owned enum/match HIR metadata for bounded WASM lowering.
//
// The enum/match module already sits at the storage-buffer limit on common
// WebGPU adapters. This pass compacts match and arm facts into one uint4 table
// so lowering can consume parser records without rebinding every source array.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_match_scrutinee_node;
StructuredBuffer<uint> hir_match_arm_start;
StructuredBuffer<uint> hir_match_arm_count;
StructuredBuffer<uint> hir_match_arm_pattern_node;
StructuredBuffer<uint> hir_match_arm_payload_start;
StructuredBuffer<uint> hir_match_arm_payload_count;
StructuredBuffer<uint> hir_match_arm_result_node;

RWStructuredBuffer<uint4> hir_enum_match_record;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(tid);
    if (i >= gParams.n_hir_nodes)
        return;

    hir_enum_match_record[i] = uint4(INVALID, INVALID, 0u, INVALID);

    uint scrutinee = hir_match_scrutinee_node[i];
    uint arm_start = hir_match_arm_start[i];
    uint arm_count = hir_match_arm_count[i];
    if (scrutinee != INVALID || arm_count != 0u)
    {
        hir_enum_match_record[i] = uint4(scrutinee, arm_start, arm_count, INVALID);
        return;
    }

    uint pattern = hir_match_arm_pattern_node[i];
    uint result = hir_match_arm_result_node[i];
    if (pattern != INVALID || result != INVALID)
    {
        hir_enum_match_record[i] = uint4(
            pattern,
            hir_match_arm_payload_start[i],
            hir_match_arm_payload_count[i],
            result);
    }
}
