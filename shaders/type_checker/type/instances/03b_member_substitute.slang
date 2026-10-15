// Publish the visible type of each already-substituted member field.
// The chain pass applies receiver environments exactly once. Symbolic leaves
// that remain belong to the enclosing generic body and await specialization.
import type_checker.checked_type_graph;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> member_result_context_instance;

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

// A checked instance reference outside any receiver scope: a type row.
bool checked_row_reference(uint row)
{
    if (row >= checked_type_capacity()) return false;
    uint kind = type_instance_kind[row];
    return kind >= 1u && kind <= 4u;
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

    // The chain pass already substituted each field in its receiver scope.
    // A surviving symbolic leaf belongs to the enclosing generic function;
    // substituting it again would confuse that function's slot with a field's.
    // So the reference is published as it is; it only has to name a row.
    if (tag == TYPE_REF_INSTANCE && !checked_row_reference(payload))
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
