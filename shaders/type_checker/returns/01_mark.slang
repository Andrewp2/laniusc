import hir_records;

// Propagate guaranteed-return facts from explicit returns through enclosing
// if/else controls.  Each if row is a two-bit atomic latch: the thread which
// completes both arms exclusively carries the fact toward the parent.  This
// makes nesting depth a data property rather than a host-recorded pass count.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_block;
StructuredBuffer<uint> compact_hir_nearest_control;
StructuredBuffer<uint> compact_hir_nearest_fn;

RWStructuredBuffer<uint> return_fn_flags;
RWStructuredBuffer<uint> return_block_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint THEN_ARM_RETURNED = 1u;
static const uint ELSE_ARM_RETURNED = 2u;
static const uint BOTH_ARMS_RETURNED = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool return_statement_node(uint node)
{
    return valid_node(node) &&
           compact_hir_core[node].kind == HIR_RETURN_STMT &&
           compact_hir_payload[node].a == STMT_RECORD_KIND_RETURN;
}

uint arm_bit(uint control, uint returning_node)
{
    if (!valid_node(control) || !valid_node(returning_node))
        return 0u;
    HirPayload control_payload = compact_hir_payload[control];
    uint block = compact_hir_nearest_block[returning_node];
    if (returning_node == control_payload.c || block == control_payload.c)
        return THEN_ARM_RETURNED;
    if (returning_node == control_payload.d || block == control_payload.d)
        return ELSE_ARM_RETURNED;
    return 0u;
}

void publish_guaranteed_return(uint node)
{
    uint current = node;
    while (valid_node(current))
    {
        uint control = compact_hir_nearest_control[current];
        if (!valid_node(control))
        {
            uint fn_node = compact_hir_nearest_fn[current];
            if (valid_node(fn_node) && compact_hir_core[fn_node].kind == HIR_FN)
                InterlockedMax(return_fn_flags[fn_node], 1u);
            return;
        }
        if (compact_hir_core[control].kind != HIR_IF_STMT)
            return;

        uint bit = arm_bit(control, current);
        if (bit == 0u)
            return;
        uint prior;
        InterlockedOr(return_block_flags[control], bit, prior);
        // Another guaranteed statement in this arm has already published the
        // same fact, or the sibling arm is not yet known to return.
        if ((prior & bit) != 0u || (prior | bit) != BOTH_ARMS_RETURNED)
            return;

        current = control;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!return_statement_node(node))
        return;
    publish_guaranteed_return(node);
}
