// Substitute generic member field refs through receiver instances.
//
// Member field projection records declaration-side refs. If the selected field
// is a generic parameter, this pass substitutes the corresponding receiver type
// argument and then publishes the token's semantic visible type.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> member_result_context_instance;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;

RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        return visible_type[payload];
    return TY_UNKNOWN;
}

void publish_substituted_member_ref(uint member_token)
{
    uint tag = member_result_ref_tag[member_token];
    uint payload = member_result_ref_payload[member_token];
    if (tag == TYPE_REF_INVALID)
        return;

    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint instance = member_result_context_instance[member_token];
        if (!valid_token(instance))
            return;

        uint slot = payload;
        uint arg_start = type_instance_arg_start[instance];
        uint arg_count = type_instance_arg_count[instance];
        if (arg_start == INVALID || slot >= arg_count)
            return;

        uint arg_i = arg_start + slot;
        tag = type_instance_arg_ref_tag[arg_i];
        payload = type_instance_arg_ref_payload[arg_i];
        member_result_ref_tag[member_token] = tag;
        member_result_ref_payload[member_token] = payload;
    }

    uint ty = type_ref_to_type_code(tag, payload);
    if (ty != TY_UNKNOWN)
        visible_type[member_token] = ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id(dtid);
    if (!valid_token(token))
        return;
    publish_substituted_member_ref(token);
}
