// Substitute generic member field refs through receiver instances.
//
// Member field projection records declaration-side refs. If the selected field
// is a generic parameter, this pass substitutes the corresponding receiver type
// argument and then publishes the token's semantic visible type.

import status;

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
StructuredBuffer<uint> type_generic_param_slot_by_token;

RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;

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

uint arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

bool instance_arg_unsupported_for_member_substitution(uint instance_i, uint slot)
{
    if (!valid_token(instance_i) || slot >= type_instance_arg_count[instance_i])
        return false;

    uint ref_i = arg_ref_index(instance_i, slot);
    if (ref_i == INVALID)
        return true;

    uint tag = type_instance_arg_ref_tag[ref_i];
    return tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_INSTANCE;
}

bool instance_ref_needs_leaf_rows(uint instance_i)
{
    if (!valid_token(instance_i))
        return false;

    uint arg_count = type_instance_arg_count[instance_i];
    if (arg_count == 0u)
        return false;
    if (arg_count > 4u || type_instance_arg_start[instance_i] == INVALID)
        return true;

    return instance_arg_unsupported_for_member_substitution(instance_i, 0u) ||
           instance_arg_unsupported_for_member_substitution(instance_i, 1u) ||
           instance_arg_unsupported_for_member_substitution(instance_i, 2u) ||
           instance_arg_unsupported_for_member_substitution(instance_i, 3u);
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : payload;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
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

    if (tag == TYPE_REF_INSTANCE && instance_ref_needs_leaf_rows(payload))
    {
        record_min_token_error(status, member_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
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
