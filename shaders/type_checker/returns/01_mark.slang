import hir_records;
import primitive_types;

// Propagate guaranteed-return facts from explicit returns through enclosing
// if/else controls.  Each if row is a two-bit atomic latch: the thread which
// completes both arms exclusively carries the fact toward the parent.  This
// makes nesting depth a data property rather than a host-recorded pass count.
// A match is a counting latch over its block arms (`pattern -> { ... }`):
// each arm block's flag is set once, by the first fact that reaches it, and
// the thread that brings the count to the arm count carries the fact on, so
// a match whose every arm is a returning block returns.

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

// The synthesized type of each expression; a call of a `-> !` function is
// scalar never.
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
// Language intrinsic tags by callee token (calls/02c_intrinsics): 2 is
// assert. Call rows list their arguments in compact_call_args from payload.b.
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
RWStructuredBuffer<uint> return_fn_flags;
RWStructuredBuffer<uint> return_block_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint INTRINSIC_ASSERT = 2u;
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

// `assert(false)`: the assert intrinsic with the literal `false` as its one
// argument always traps, so it diverges like a call of a `-> !` function.
// This is how a `-> !` body that calls no other one (core::panic::panic)
// proves that it does not return.
bool assert_false_call(uint node)
{
    HirPayload call = compact_hir_payload[node];
    uint callee = call.a;
    if (!valid_node(callee) || call.c != 1u || call.b >= compact_call_arg_count[0u])
        return false;
    HirCore callee_core = compact_hir_core[callee];
    if (callee_core.kind == HIR_MEMBER_EXPR) return false;
    uint token = compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = callee_core.token_start;
    if (token >= gParams.n_tokens || call_intrinsic_tag[token] != INTRINSIC_ASSERT)
        return false;
    HirCallArg argument = compact_call_args[call.b];
    return argument.call == node && valid_node(argument.value) &&
           compact_hir_core[argument.value].kind == HIR_LITERAL_EXPR &&
           compact_hir_payload[argument.value].a == HIR_EXPR_FALSE;
}

// A diverging call that is a whole expression statement (`fail();`) ends its
// block like a return: a call of type never (a `-> !` function) or
// `assert(false)`. Compaction drops the expression-statement row, so such a
// call is a direct child of its block.
bool diverging_statement_call(uint node)
{
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_CALL_EXPR)
        return false;
    uint block = compact_hir_core[node].parent;
    if (!valid_node(block) || compact_hir_core[block].kind != HIR_BLOCK)
        return false;
    return type_ref_is_never(call_inference_result_tag[node], call_inference_result_payload[node]) ||
           assert_false_call(node);
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

// Whether `block` is the block of one of `match`'s arms.
bool arm_block_of(uint match, uint block)
{
    if (!valid_node(block) || compact_hir_core[block].kind != HIR_BLOCK)
        return false;
    HirPayload value = compact_hir_payload[match];
    uint total = compact_match_arm_count[0u];
    if (value.b >= total || value.c > total - value.b)
        return false;
    for (uint ordinal = 0u; ordinal < value.c; ordinal++)
    {
        if (compact_match_arms[value.b + ordinal].result == block)
            return true;
    }
    return false;
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
        if (compact_hir_core[control].kind == HIR_MATCH_EXPR)
        {
            uint block = compact_hir_nearest_block[current];
            if (!arm_block_of(control, block))
                return;
            uint first;
            InterlockedOr(return_block_flags[block], 1u, first);
            if (first != 0u)
                return;
            uint returned;
            InterlockedAdd(return_block_flags[control], 1u, returned);
            if (returned + 1u != compact_hir_payload[control].c)
                return;
            current = control;
            continue;
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
    if (return_statement_node(node))
        publish_guaranteed_return(node);
    else if (diverging_statement_call(node))
        publish_guaranteed_return(node);
}
