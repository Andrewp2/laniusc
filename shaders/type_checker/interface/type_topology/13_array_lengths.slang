// Attach checked array-length semantics to already-emitted array records.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_hir_order;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint RECORD_WORDS = 9u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail)
{
    atomic_u32_or(interface_status, 0u, 2048u);
    atomic_u32_min(interface_status, 1u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = linear_thread_id(dtid);
    if (index >= min(interface_type_count[0u], gParams.hir_capacity))
        return;
    uint node = interface_type_hir_order[index];
    if (node >= gParams.hir_capacity || hir_type_form[node] != HIR_TYPE_FORM_ARRAY)
        return;
    uint kind = TYPE_LEN_LITERAL;
    uint payload = hir_type_len_value[node];
    if (payload == INVALID)
    {
        uint token = hir_type_len_token[node];
        payload = token < gParams.token_capacity
                    ? type_const_param_slot_by_token[token]
                    : INVALID;
        kind = TYPE_LEN_CONST_PARAM;
    }
    if (payload == INVALID)
    {
        fail(node);
        return;
    }
    uint base = index * RECORD_WORDS;
    interface_types[base + 5u] = kind;
    interface_types[base + 6u] = payload;
    interface_types[base + 7u] = 0u;
}
