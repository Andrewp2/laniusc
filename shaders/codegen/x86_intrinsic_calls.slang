// x86_64 intrinsic call statement projection.
//
// This pass consumes type-check intrinsic tags plus parser/backend call records
// and scatters a stable per-call-node record for intrinsic expression
// statements. It does not inspect source text, token spelling, or token
// neighborhoods; later instruction-count and instruction-generation passes can
// consume these rows as ordinary body statement records.

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint4> x86_call_type_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint> call_arg_lookup_status;
StructuredBuffer<uint> call_intrinsic_tag;

RWStructuredBuffer<uint4> x86_intrinsic_call_record;
RWStructuredBuffer<uint> x86_intrinsic_call_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_STMT = 7u;
static const uint HIR_CALL_EXPR = 19u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_LOOKUP_OK = 1u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint INTRINSIC_NONE = 0u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
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

bool call_records_ok()
{
    return call_record_status[0u] == X86_CALL_RECORDS_OK && call_record_status[1u] == 0u;
}

bool call_arg_lookup_ok()
{
    return call_arg_lookup_status[0u] == X86_CALL_ARG_LOOKUP_OK &&
           call_arg_lookup_status[1u] == 0u;
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint nearest_hir_statement(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 128u && valid_node(node); guard += 1u)
    {
        if (hir_kind[node] == HIR_STMT)
            return node;
        node = parent_node(node);
    }
    return INVALID;
}

bool intrinsic_call_statement(uint call_node, out uint intrinsic_tag)
{
    intrinsic_tag = INTRINSIC_NONE;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR ||
        !has_call_record(call_node))
        return false;

    uint stmt = nearest_hir_statement(call_node);
    if (!valid_node(stmt))
        return false;

    uint callee_token = x86_call_type_record[call_node].z;
    if (!valid_token(callee_token))
        return false;

    intrinsic_tag = call_intrinsic_tag[callee_token];
    return intrinsic_tag != INTRINSIC_NONE;
}

uint first_arg_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || x86_call_record[call_node].w == 0u)
        return INVALID;

    uint active_nodes = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < active_nodes; node += 1u)
    {
        if (hir_call_arg_parent_call[node] == call_node &&
            hir_call_arg_ordinal[node] == 0u)
            return node;
    }

    uint4 lookup = x86_call_arg_lookup_record[call_node * X86_SYSV_MAX_INTEGER_ARGS];
    if (lookup.x != call_node || lookup.y != 0u)
        return INVALID;
    return valid_node(lookup.z) ? lookup.z : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    bool upstream_ok = call_records_ok() && call_arg_lookup_ok();
    if (node_i == 0u)
    {
        x86_intrinsic_call_status[0u] = upstream_ok ? X86_INTRINSIC_CALLS_OK : 0u;
        x86_intrinsic_call_status[1u] = upstream_ok ? 0u :
                                        (call_records_ok() ? call_arg_lookup_status[1u] :
                                         call_record_status[1u]);
        x86_intrinsic_call_status[2u] = upstream_ok ? INVALID :
                                        (call_records_ok() ? call_arg_lookup_status[2u] :
                                         call_record_status[2u]);
        x86_intrinsic_call_status[3u] = 0u;
    }

    if (!upstream_ok || node_i >= active_hir_node_count())
        return;

    uint intrinsic_tag = INTRINSIC_NONE;
    if (!intrinsic_call_statement(node_i, intrinsic_tag))
        return;

    uint owner_fn = x86_call_record[node_i].x;
    uint arg0_node = first_arg_node_for_call(node_i);
    x86_intrinsic_call_record[node_i] = uint4(owner_fn, node_i, arg0_node, intrinsic_tag);

    uint old_count = 0u;
    InterlockedAdd(x86_intrinsic_call_status[3u], 1u, old_count);
}
