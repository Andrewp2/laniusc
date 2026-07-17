// x86_64 match-to-return ownership projection.
//
// This pass materializes direct return-statement/match-expression relations
// from HIR statement records and expression-forward resolution. Later x86
// stages consume the arrays instead of rediscovering this relationship from
// token neighborhoods or helper names.

import atomics;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_enclosing_return_node;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> x86_compact_executable_raw;

RWStructuredBuffer<uint> x86_match_return_node;
RWStructuredBuffer<uint4> x86_match_record;
RWStructuredBuffer<uint4> x86_match_arm_record;
RWStructuredBuffer<uint> x86_match_arm_owner;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_STMT = 7u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool valid_dense(uint node)
{
    return node != INVALID && node < min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool is_return_stmt(uint node)
{
    if (!valid_node(node) || stmt_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
        return false;
    uint kind = hir_kind[node];
    return kind == HIR_RETURN_STMT || kind == HIR_STMT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint return_node = linear_dispatch_id(tid);
    if (!valid_node(return_node))
        return;

    uint arm_count = min(compact_match_arm_count[0u], gParams.n_hir_nodes);
    if (return_node < arm_count)
    {
        uint owner_dense = compact_match_arms[return_node].owner;
        uint owner_raw = valid_dense(owner_dense)
                             ? x86_compact_executable_raw[owner_dense]
                             : INVALID;
        uint result_dense = compact_match_arms[return_node].result;
        uint result_raw = valid_dense(result_dense)
                              ? x86_compact_executable_raw[result_dense]
                              : INVALID;
        if (valid_node(owner_raw))
            x86_match_arm_owner[return_node] = owner_raw;
        if (valid_node(result_raw))
        {
            uint4 arm_record = x86_match_arm_record[return_node];
            arm_record.w = result_raw;
            x86_match_arm_record[return_node] = arm_record;
        }
    }

    uint dense = raw_to_compact_hir[return_node];
    if (valid_dense(dense) && compact_hir_core[dense].kind == HIR_MATCH_EXPR)
    {
        uint scrutinee_dense = compact_hir_payload[dense].a;
        uint scrutinee_raw = valid_dense(scrutinee_dense)
                                   ? x86_compact_executable_raw[scrutinee_dense]
                                   : INVALID;
        if (valid_node(scrutinee_raw))
        {
            uint4 record = x86_match_record[return_node];
            record.x = scrutinee_raw;
            x86_match_record[return_node] = record;
        }
    }

    if (!is_return_stmt(return_node))
        return;

    uint return_expr = stmt_slot(return_node, 1u);
    uint match_node = resolve_expr(return_expr);
    uint enclosing_return =
        valid_node(match_node) ? x86_enclosing_return_node[match_node] : INVALID;
    if (!valid_node(match_node) ||
        hir_kind[match_node] != HIR_MATCH_EXPR ||
        enclosing_return != return_node)
        return;

    atomic_u32_min(x86_match_return_node, match_node, return_node);
}
