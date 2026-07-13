// Clear parser-owned enum variant and match-arm metadata.
//
// Follow-up enum/match passes seed grammar list links, pointer-jump ordinals,
// and scatter owner/count records. This pass intentionally does not inspect
// source bytes, token spelling, helper names, or function bodies.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirEnumMatch;

RWStructuredBuffer<uint> hir_variant_parent_enum;
RWStructuredBuffer<uint> hir_variant_ordinal;
RWStructuredBuffer<uint> hir_variant_payload_start;
RWStructuredBuffer<uint> hir_variant_payload_count;
RWStructuredBuffer<uint> hir_variant_payload_node;
RWStructuredBuffer<uint> hir_match_scrutinee_node;
RWStructuredBuffer<uint> hir_match_arm_start;
RWStructuredBuffer<uint> hir_match_arm_count;
RWStructuredBuffer<uint> hir_match_arm_next;
RWStructuredBuffer<uint> hir_match_arm_pattern_node;
RWStructuredBuffer<uint> hir_match_pattern_owner_arm;
RWStructuredBuffer<uint> hir_match_arm_payload_start;
RWStructuredBuffer<uint> hir_match_arm_payload_count;
RWStructuredBuffer<uint> hir_match_arm_result_node;
RWStructuredBuffer<uint> hir_match_payload_owner_arm;
RWStructuredBuffer<uint> hir_match_payload_match_node;
RWStructuredBuffer<uint> hir_match_payload_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint VARIANT_PAYLOAD_SLOT_STRIDE = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirEnumMatch.n)
        return;

    hir_variant_parent_enum[node] = INVALID;
    hir_variant_ordinal[node] = INVALID;
    hir_variant_payload_start[node] = INVALID;
    hir_variant_payload_count[node] = 0u;
    hir_variant_payload_node[node * VARIANT_PAYLOAD_SLOT_STRIDE + 0u] = INVALID;
    hir_variant_payload_node[node * VARIANT_PAYLOAD_SLOT_STRIDE + 1u] = INVALID;
    hir_variant_payload_node[node * VARIANT_PAYLOAD_SLOT_STRIDE + 2u] = INVALID;
    hir_variant_payload_node[node * VARIANT_PAYLOAD_SLOT_STRIDE + 3u] = INVALID;
    hir_match_scrutinee_node[node] = INVALID;
    hir_match_arm_start[node] = INVALID;
    hir_match_arm_count[node] = 0u;
    hir_match_arm_next[node] = INVALID;
    hir_match_arm_pattern_node[node] = INVALID;
    hir_match_pattern_owner_arm[node] = INVALID;
    hir_match_arm_payload_start[node] = INVALID;
    hir_match_arm_payload_count[node] = 0u;
    hir_match_arm_result_node[node] = INVALID;
    hir_match_payload_owner_arm[node] = INVALID;
    hir_match_payload_match_node[node] = INVALID;
    hir_match_payload_ordinal[node] = INVALID;
}
