// Project compact HIR match metadata into the legacy raw-node x86 planner.
//
// Match expressions remain keyed by their raw semantic representative until
// the x86 instruction planner is dense-HIR-native. Match arms are compact
// family rows; raw grammar productions never cross this boundary.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
struct HirMatchPayload { uint arm; uint pattern; uint ordinal; uint file_id; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_node_func;

RWStructuredBuffer<uint4> x86_match_record;
RWStructuredBuffer<uint4> x86_match_arm_record;
RWStructuredBuffer<uint> x86_match_result_dense_owner;
RWStructuredBuffer<uint> x86_match_arm_owner;
RWStructuredBuffer<uint> x86_match_pattern_owner;
RWStructuredBuffer<uint> x86_compact_executable_raw;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint MATCH_ARM_VARIANT_UNKNOWN = 0xffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint active_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

bool valid_raw(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_dense(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_arm(uint arm)
{
    return arm != INVALID && arm < active_arm_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

bool expression_kind_requires_payload(uint kind)
{
    return kind == HIR_EXPR || kind == HIR_ASSIGN_EXPR ||
           kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR ||
           kind == HIR_POSTFIX_EXPR || kind == HIR_NAME_EXPR ||
           kind == HIR_LITERAL_EXPR;
}

bool is_executable_projection(uint raw, uint dense)
{
    if (!valid_raw(raw) || !valid_dense(dense) ||
        hir_kind[raw] != compact_hir_core[dense].kind ||
        !valid_raw(x86_node_func[raw]))
        return false;
    uint kind = hir_kind[raw];
    return !expression_kind_requires_payload(kind) ||
           hir_expr_record[raw * EXPR_RECORD_STRIDE] > HIR_EXPR_FORWARD;
}

uint payload_token_for_arm(uint arm)
{
    uint count = compact_match_payload_count[arm];
    uint start = compact_match_payload_start[arm];
    if (count == 0u || start == INVALID)
        return INVALID;
    HirMatchPayload payload = compact_match_payloads[start];
    if (!valid_dense(payload.pattern))
        return INVALID;
    uint token = compact_hir_core[payload.pattern].token_start;
    return valid_token(token) ? token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    if (row >= gParams.n_hir_nodes)
        return;

    uint dense = raw_to_compact_hir[row];
    if (is_executable_projection(row, dense))
        atomic_u32_min(x86_compact_executable_raw, dense, row);

    if (!has_match_feature())
        return;

    x86_match_record[row] = uint4(INVALID, INVALID, 0u, INVALID);
    x86_match_arm_record[row] = uint4(INVALID, INVALID, 0u, INVALID);

    if (valid_dense(dense) && compact_hir_core[dense].kind == HIR_MATCH_EXPR)
    {
        HirPayload payload = compact_hir_payload[dense];
        x86_match_record[row] = uint4(
            INVALID, payload.b, payload.c, INVALID);
    }

    if (!valid_arm(row))
    {
        uint payload_rows = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
        if (row < payload_rows)
        {
            HirMatchPayload payload = compact_match_payloads[row];
            if (valid_dense(payload.pattern) && valid_arm(payload.arm))
                x86_match_pattern_owner[payload.pattern] = payload.arm;
        }
        return;
    }

    HirMatchArm arm = compact_match_arms[row];
    uint payload_count = min(compact_match_payload_count[row], 0xffffu);
    x86_match_arm_record[row] = uint4(
        arm.pattern,
        payload_token_for_arm(row),
        pack_u16_pair(payload_count, MATCH_ARM_VARIANT_UNKNOWN),
        INVALID);

    if (valid_dense(arm.result))
        x86_match_result_dense_owner[arm.result] = row;

    uint payload_rows = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
    if (row < payload_rows)
    {
        HirMatchPayload payload = compact_match_payloads[row];
        if (valid_dense(payload.pattern) && valid_arm(payload.arm))
            x86_match_pattern_owner[payload.pattern] = payload.arm;
    }
}
