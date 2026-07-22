// Publish target-independent aggregate result metadata by dense call-site ID.
//
// This pass runs after direct, qualified, and method call resolution. Named
// return instances do not depend on argument-row existence, so zero-argument
// calls receive the same compact semantic fact as calls with arguments.
// Array and slice results remain owned by their dedicated inference passes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> call_result_instance;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint callee_token(uint call)
{
    uint call_token = compact_hir_core[call].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee))
        return valid_token(call_token) ? call_token : INVALID;

    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token))
        token = core.token_start;
    return valid_token(token) ? token : call_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_thread_id(dtid);
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return;

    uint token = callee_token(call);
    uint fn = valid_token(token) ? call_fn_index[token] : INVALID;
    if (!valid_token(fn) || fn_return_ref_tag[fn] != TYPE_REF_INSTANCE)
        return;

    uint instance = fn_return_ref_payload[fn];
    if (!valid_token(instance) || type_instance_kind[instance] != TYPE_INSTANCE_NAMED)
        return;
    call_result_instance[call] = instance;
}
