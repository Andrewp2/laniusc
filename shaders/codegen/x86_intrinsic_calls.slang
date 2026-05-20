// x86_64 intrinsic call statement projection.
//
// This pass consumes type-check intrinsic tags plus parser/backend call records
// and scatters a stable per-call-node record for intrinsic expression
// statements. It does not inspect source text, token spelling, or token
// neighborhoods, and it consumes a pointer-jumped enclosing-statement record
// instead of walking parent chains in this projection.

import gpu_index;
import status;

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
StructuredBuffer<uint> x86_enclosing_stmt_node;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> x86_call_type_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint> call_intrinsic_tag;

RWStructuredBuffer<uint> x86_intrinsic_call_record;
RWStructuredBuffer<uint> x86_intrinsic_call_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_STMT = 7u;
static const uint HIR_CALL_EXPR = 19u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_ERR_INTRINSIC_CALLS = 21u;
static const uint X86_INTRINSIC_TAG_BITS = 4u;
static const uint X86_INTRINSIC_TAG_MASK = 0x0fu;
static const uint X86_INTRINSIC_CALL_BASE_MAX = 0x0fffffffu;
static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint INTRINSIC_NONE = 0u;

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

bool valid_token(uint token)
{
    return valid_index_or_invalid(token, gParams.n_tokens, INVALID);
}

uint call_lookup_base(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint token = x86_call_record[call_node].z;
    return valid_token(token) ? token : INVALID;
}

bool call_records_ok()
{
    return stage_status4_ok(call_record_status, X86_CALL_RECORDS_OK);
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return uint4_any_not_equal(record, INVALID);
}

uint call_type_word(uint call_node, uint slot)
{
    return row_major_load<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        slot,
        INVALID);
}

uint nearest_hir_statement(uint node)
{
    return valid_node(node) ? x86_enclosing_stmt_node[node] : INVALID;
}

bool intrinsic_call_statement(uint call_node, out uint intrinsic_tag)
{
    intrinsic_tag = INTRINSIC_NONE;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR ||
        !has_call_record(call_node))
        return false;

    uint stmt = nearest_hir_statement(call_node);
    if (!valid_node(stmt) || hir_kind[stmt] != HIR_STMT)
        return false;

    uint callee_token = call_type_word(call_node, 2u);
    if (!valid_token(callee_token))
        return false;

    intrinsic_tag = call_intrinsic_tag[callee_token];
    return intrinsic_tag != INTRINSIC_NONE;
}

uint pack_intrinsic_call_record(uint base, uint intrinsic_tag)
{
    if (!valid_token(base) ||
        base > X86_INTRINSIC_CALL_BASE_MAX ||
        intrinsic_tag > X86_INTRINSIC_TAG_MASK)
        return INVALID;
    return (base << X86_INTRINSIC_TAG_BITS) |
           (intrinsic_tag & X86_INTRINSIC_TAG_MASK);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
        write_stage_status4_from_upstream1(
            x86_intrinsic_call_status,
            call_records_ok(),
            X86_INTRINSIC_CALLS_OK,
            INVALID,
            0u,
            call_record_status,
            0u,
            INVALID);

    if (!call_records_ok() || node_i >= active_hir_node_count())
        return;

    if (!has_call_record(node_i))
        return;

    uint intrinsic_tag = INTRINSIC_NONE;
    bool is_intrinsic = intrinsic_call_statement(node_i, intrinsic_tag);
    uint base = call_lookup_base(node_i);
    if (base == INVALID)
        return;

    uint packed = pack_intrinsic_call_record(
        base,
        is_intrinsic ? intrinsic_tag : INTRINSIC_NONE);
    if (packed == INVALID)
    {
        publish_stage_error_min_detail4(
            x86_intrinsic_call_status,
            X86_ERR_INTRINSIC_CALLS,
            node_i);
        return;
    }

    x86_intrinsic_call_record[node_i] = packed;
}
