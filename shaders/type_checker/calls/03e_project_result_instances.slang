import hir_records;

// Seed complete declaration-side result references by dense call-site ID.
//
// This pass runs after direct, qualified, and method call resolution. Every
// compound return carries its checked type graph, including element types and
// array lengths, before dependent call inference begins. Argument inference
// accepts a seeded graph only when it is closed; symbolic return templates
// still require materialization under the callee's accepted environment.

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
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> call_result_instance;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TYPE_REF_INSTANCE = 3u;
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
    uint callee = compact_hir_payload[call].a;
    // A member's leaf owns this call; its span can begin in a receiver call.
    if (valid_hir(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee].c;
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint call_token = compact_hir_core[call].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    if (!valid_hir(callee))
        return valid_token(call_token) ? call_token : INVALID;

    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = payload.d;
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
    if (!valid_token(instance) || type_instance_kind[instance] == 0u)
        return;
    call_result_instance[call] = instance;
}
