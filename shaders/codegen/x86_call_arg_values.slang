// x86_64 call-argument lookup projection over HIR call records.
//
// This pass scatters the parser-owned call argument links into a compact
// per-call/per-ordinal lookup table. Argument expression lowering remains in
// the instruction-count and instruction-generation stages.

import gpu_index;
import hir_records;
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
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_call_record;

RWStructuredBuffer<uint> x86_call_arg_lookup_record;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_LOOKUP_SLOTS = 4u;
static const uint X86_CALL_ARG_LOOKUP_KIND_BITS = 4u;

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

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool is_method_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    if (!valid_node(callee_node) || hir_kind[callee_node] != HIR_MEMBER_EXPR)
        return INVALID;
    return hir_member_receiver_node[callee_node];
}

void write_call_arg_lookup_record(
    uint arg_node,
    uint call_node,
    uint ordinal)
{
    if (!valid_node(arg_node))
        return;

    uint arg_count = x86_call_record[call_node].w;
    if (ordinal >= arg_count || ordinal >= X86_CALL_ARG_LOOKUP_SLOTS)
        return;

    uint token = x86_call_record[call_node].z;
    if (!valid_token(token))
        return;

    uint packed = arg_node << X86_CALL_ARG_LOOKUP_KIND_BITS;
    if ((packed >> X86_CALL_ARG_LOOKUP_KIND_BITS) != arg_node)
        return;

    uint slot = row_major_slot(token, X86_CALL_ARG_LOOKUP_SLOTS, ordinal);
    x86_call_arg_lookup_record[slot] = packed;
}

void publish_method_receiver_arg(uint call_node)
{
    uint receiver_node = method_receiver_node_for_call(call_node);
    if (!valid_node(receiver_node))
        return;

    uint4 call_record = x86_call_record[call_node];
    if (call_record.w == 0u)
        return;

    write_call_arg_lookup_record(receiver_node, call_node, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (!call_records_ok() || node_i >= active_hir_node_count())
        return;

    if (has_call_record(node_i) && is_method_call(node_i))
        publish_method_receiver_arg(node_i);

    uint packed_arg = hir_call_arg_parent_call[node_i];
    uint call_node = hir_node_ordinal_node(packed_arg);
    if (!has_call_record(call_node))
        return;

    uint ordinal = hir_node_ordinal_ordinal(packed_arg) + (is_method_call(call_node) ? 1u : 0u);
    if (ordinal >= x86_call_record[call_node].w)
        return;

    write_call_arg_lookup_record(node_i, call_node, ordinal);
}
