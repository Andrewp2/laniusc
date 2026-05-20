// x86_64 match-pattern arm finalization.
//
// Consumes per-node pattern candidate records and writes the packed match-arm
// variant/payload metadata. This keeps the arm pass local to its record instead
// of rescanning the pattern subtree.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> x86_match_pattern_node_variant;
StructuredBuffer<uint> x86_match_pattern_node_payload_decl;
StructuredBuffer<uint> x86_match_pattern_first_use_node;
StructuredBuffer<uint> x86_match_pattern_first_variant_node;
StructuredBuffer<uint> x86_match_pattern_first_payload_node;

RWStructuredBuffer<uint4> x86_match_record;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MATCH_ARM_VARIANT_UNKNOWN = 0xffffu;
static const uint MATCH_ARM_VARIANT_UNRESOLVED = 0xfffeu;
static const uint MATCH_ARM_VARIANT_NO_USE_TOKEN = 0xfffdu;
static const uint MATCH_ARM_VARIANT_NO_VARIANT = 0xfffcu;
static const uint HIR_MATCH_EXPR = 34u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint arm = linear_dispatch_id(tid);
    if (!valid_node(arm))
        return;
    if (hir_kind[arm] == HIR_MATCH_EXPR)
        return;

    uint4 record = x86_match_record[arm];
    if (!valid_node(record.x) || !valid_node(record.w))
        return;

    uint payload_count = unpack_u16_pair_low(record.z);
    uint payload_decl = record.y;
    uint first_payload = x86_match_pattern_first_payload_node[arm];
    if (!valid_token(payload_decl) && valid_node(first_payload))
        payload_decl = x86_match_pattern_node_payload_decl[first_payload];

    uint first_variant = x86_match_pattern_first_variant_node[arm];
    if (valid_node(first_variant))
    {
        uint ordinal = x86_match_pattern_node_variant[first_variant];
        if (ordinal >= MATCH_ARM_VARIANT_UNKNOWN)
            ordinal = MATCH_ARM_VARIANT_UNRESOLVED;
        x86_match_record[arm] = uint4(
            record.x,
            payload_decl,
            pack_u16_pair(payload_count, ordinal),
            record.w);
        return;
    }

    uint first_use = x86_match_pattern_first_use_node[arm];
    uint reason = valid_node(first_use)
        ? MATCH_ARM_VARIANT_NO_VARIANT
        : MATCH_ARM_VARIANT_NO_USE_TOKEN;
    x86_match_record[arm] = uint4(
        record.x,
        payload_decl,
        pack_u16_pair(payload_count, reason),
        record.w);
}
