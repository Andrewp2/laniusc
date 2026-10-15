// Substitute generic struct-literal field refs through contextual instances.
//
// The preceding HIR pass publishes declaration-side field refs and context
// instance tokens. This pass is token-indexed: each field's declared type is
// substituted under its context application over canonical IDs and realized
// as a checked row (ct_scoped.slang).
import type_checker.mutable_checked_type_graph;
import type_checker.substitution.ct_scoped;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> struct_init_field_expected_context_instance;

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
    uint instance_i = struct_init_field_expected_context_instance[field_token];
    uint failure;
    if ((tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_INSTANCE) && !ct_scoped_reference(
        tag, payload, instance_i, gParams.n_tokens, tag, payload, failure))
    {
        // A busy row was another lane's to write; it is reported as a
        // mismatch too, as a missing row was.
        record_min_token_error(status, field_token, ERR_ASSIGN_MISMATCH, failure);
        return;
    }

    struct_init_field_expected_ref_tag[field_token] = tag;
    struct_init_field_expected_ref_payload[field_token] = payload;
    // Expected references are now in caller scope. The independent record
    // owner column still identifies the constructor's field/layout owner.
    struct_init_field_expected_context_instance[field_token] = INVALID;
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
