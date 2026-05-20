// Pack parser-owned match HIR metadata for x86 lowering.
//
// Downstream x86 passes stay under WebGPU storage-buffer limits by consuming
// one packed record table instead of rebinding every parser match array.

import gpu_index;
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
StructuredBuffer<uint> hir_match_arm_next;
StructuredBuffer<uint> hir_match_arm_pattern_node;
StructuredBuffer<uint> hir_match_arm_payload_start;
StructuredBuffer<uint> hir_match_arm_payload_count;
StructuredBuffer<uint> hir_match_arm_result_node;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint4> x86_match_record;
RWStructuredBuffer<uint> x86_match_result_value_owner;
RWStructuredBuffer<uint> x86_match_arm_owner;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MATCH_ARM_VARIANT_UNKNOWN = 0xffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint token_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    return valid_token(token) ? token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= gParams.n_hir_nodes)
        return;

    x86_match_record[node] = uint4(INVALID, INVALID, 0u, INVALID);

    uint scrutinee = hir_match_scrutinee_node[node];
    uint arm_start = hir_match_arm_start[node];
    uint arm_count = hir_match_arm_count[node];
    if (scrutinee != INVALID || arm_count != 0u)
    {
        uint second_arm = arm_count > 1u && valid_node(arm_start)
                              ? hir_match_arm_next[arm_start]
                              : INVALID;
        x86_match_record[node] = uint4(scrutinee, arm_start, arm_count, second_arm);
        if (valid_node(arm_start))
            x86_match_arm_owner[arm_start] = node;
        if (valid_node(second_arm))
            x86_match_arm_owner[second_arm] = node;
        return;
    }

    uint pattern = hir_match_arm_pattern_node[node];
    uint result = hir_match_arm_result_node[node];
    if (pattern != INVALID || result != INVALID)
    {
        uint payload_node = hir_match_arm_payload_start[node];
        uint payload_token = token_for_node(payload_node);
        uint payload_count = unpack_u16_pair_low(hir_match_arm_payload_count[node]);
        x86_match_record[node] = uint4(
            pattern,
            payload_token,
            pack_u16_pair(payload_count, MATCH_ARM_VARIANT_UNKNOWN),
            result);
        if (valid_node(result))
            x86_match_result_value_owner[result] = node;
    }
}
