// Substitute generic struct-literal field refs through contextual instances.
//
// The preceding HIR pass publishes declaration-side field refs and context
// instance tokens. This pass is token-indexed and consumes only type-instance
// argument arrays to materialize concrete expected field types.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> struct_init_field_context_instance;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;

RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
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

bool valid_token(uint i)
{
    return i != INVALID && i < gParams.n_tokens;
}

uint arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

uint arg_row_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + slot;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || slot >= type_instance_arg_count[instance_i])
        return false;

    uint row_i = arg_row_ref_index(instance_i, slot);
    if (row_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_i];
        payload = type_instance_arg_row_ref_payload[row_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    uint ref_i = arg_ref_index(instance_i, slot);
    if (ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[ref_i];
    payload = type_instance_arg_ref_payload[ref_i];
    return tag != TYPE_REF_INVALID;
}

bool instance_arg_unsupported_for_field_substitution(uint instance_i, uint slot)
{
    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, slot, tag, payload))
        return true;

    return tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_INSTANCE;
}

bool instance_ref_needs_leaf_rows(uint instance_i)
{
    if (!valid_token(instance_i))
        return false;

    uint arg_count = type_instance_arg_count[instance_i];
    if (arg_count == 0u)
        return false;

    [loop]
    for (uint slot = 0u; slot < arg_count; slot += 1u)
    {
        if (instance_arg_unsupported_for_field_substitution(instance_i, slot))
            return true;
    }
    return false;
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

void publish_visible_field_type(uint field_token)
{
    uint tag = struct_init_field_expected_ref_tag[field_token];
    uint payload = struct_init_field_expected_ref_payload[field_token];
    uint instance_i = struct_init_field_context_instance[field_token];

    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        if (!valid_token(instance_i))
            return;
        uint slot = payload;
        if (!instance_arg_ref(instance_i, slot, tag, payload))
            return;
        struct_init_field_expected_ref_tag[field_token] = tag;
        struct_init_field_expected_ref_payload[field_token] = payload;
    }

    if (tag == TYPE_REF_INSTANCE && instance_ref_needs_leaf_rows(payload))
    {
        record_min_token_error(status, field_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    uint ty = type_ref_to_type_code(tag, payload);
    if (ty != TY_UNKNOWN)
        visible_type[field_token] = ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;
    publish_visible_field_type(i);
}
