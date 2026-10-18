// Initialize dense-HIR member/index chains from immutable root references.
import hir_records;
import gpu_index;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;
RWStructuredBuffer<uint> member_next_node;
RWStructuredBuffer<uint> member_chain_root_ref_tag;
RWStructuredBuffer<uint> member_chain_root_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint NAME_ROLE_SELF = 1u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint i) { return i != INVALID && i < count(); }
bool valid_instance(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

bool valid_token(uint i) { return i != INVALID && i < gParams.n_tokens; }

uint name_token(uint node)
{
    if (!valid_hir(node)) return INVALID;
    uint kind = compact_hir_core[node].kind;
    if (kind != HIR_NAME_EXPR && kind != HIR_PATH_EXPR) return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : INVALID;
}

bool decl_ref(uint token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    uint decl = valid_token(token) ? visible_decl[token] : INVALID;
    if (!valid_token(decl)) return false;
    tag = decl_type_ref_tag[decl]; payload = decl_type_ref_payload[decl];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

bool value_ref(uint token, out uint tag, out uint payload)
{
    if (decl_ref(token, tag, payload)) return true;
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (!valid_token(token)) return false;
    uint ty = visible_type[token];
    uint decl = visible_decl[token];
    if (ty == 0u && valid_token(decl)) ty = visible_type[decl];
    if (ty == 0u) return false;
    tag = TYPE_REF_SCALAR; payload = ty;
    return true;
}

bool call_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_CALL_EXPR) return false;
    tag = call_inference_result_tag[node]; payload = call_inference_result_payload[node];
    if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
    uint instance = call_result_instance[node];
    if (checked_instance_is_closed(instance))
    {
        tag = TYPE_REF_INSTANCE;
        payload = instance;
        return true;
    }
    uint callee = compact_hir_payload[node].a;
    uint token = name_token(callee);
    uint declaration = valid_token(token) ? call_fn_index[token] : INVALID;
    if (valid_token(declaration))
    {
        if (type_decl_generic_param_count[declaration] != 0u) return false;
        tag = fn_return_ref_tag[declaration];
        payload = fn_return_ref_payload[declaration];
        if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
    }
    uint ty = valid_token(token) ? call_return_type[token] : 0u;
    if (ty == 0u) return false;
    tag = TYPE_REF_SCALAR;
    payload = ty;
    return true;
}

bool self_ref(uint member, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    uint receiver = compact_hir_payload[member].b;
    if (!valid_hir(receiver) || compact_hir_core[receiver].kind != HIR_NAME_EXPR ||
        compact_hir_payload[receiver].b != NAME_ROLE_SELF) return false;
    uint fn = compact_hir_nearest_fn[member];
    if (!valid_hir(fn)) return false;
    uint token = compact_hir_payload[fn].b;
    if (!valid_token(token)) return false;
    tag = method_decl_receiver_ref_tag[token];
    payload = method_decl_receiver_ref_payload[token];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

// The receiver's own published expression type. Parenthesized receivers,
// struct literals and matches have no name token of their own: payload.d of
// a member is the receiver's first source token, which is `(` for a group.
bool slot_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (!valid_hir(node)) return false;
    tag = call_inference_result_tag[node]; payload = call_inference_result_payload[node];
    if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
    tag = TYPE_REF_INVALID; payload = INVALID;
    return false;
}

bool call_callee(uint member)
{
    uint parent = compact_hir_expr_parent[member];
    return valid_hir(parent) && compact_hir_core[parent].kind == HIR_CALL_EXPR &&
           compact_hir_payload[parent].a == member;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint member = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(member)) return;
    uint kind = compact_hir_core[member].kind;
    if (kind != HIR_MEMBER_EXPR && kind != HIR_INDEX_EXPR) return;
    HirPayload p = compact_hir_payload[member];
    uint token = p.c;
    // A member used as a call callee is resolved by the method/static-call
    // pipeline. This pass may run again after final result types are known;
    // it must not erase the call resolver's completed metadata.
    if (kind == HIR_MEMBER_EXPR)
    {
        if (!valid_token(token) || call_callee(member)) return;
        member_result_ref_tag[token] = TYPE_REF_INVALID;
        member_result_ref_payload[token] = INVALID;
        member_result_context_instance[token] = INVALID;
        member_result_field_ordinal[token] = INVALID;
        member_result_field_node[token] = INVALID;
    }
    member_chain_root_ref_tag[member] = TYPE_REF_INVALID;
    member_chain_root_ref_payload[member] = INVALID;

    uint receiver = p.b;
    if (valid_hir(receiver) && (compact_hir_core[receiver].kind == HIR_MEMBER_EXPR ||
        compact_hir_core[receiver].kind == HIR_INDEX_EXPR))
    {
        uint previous;
        InterlockedCompareExchange(member_next_node[receiver], INVALID, member, previous);
        return;
    }
    uint tag; uint payload;
    uint receiver_token = kind == HIR_MEMBER_EXPR && valid_token(p.d) ? p.d : name_token(receiver);
    bool found = call_ref(receiver, tag, payload) || value_ref(receiver_token, tag, payload);
    if (!found && kind == HIR_MEMBER_EXPR) found = self_ref(member, tag, payload);
    // A name inside parentheses: the receiver node is the name itself.
    uint receiver_name = name_token(receiver);
    if (!found && receiver_name != receiver_token) found = value_ref(receiver_name, tag, payload);
    // Any other receiver form reads its own slot, published by 03g in an
    // earlier round (so this lags the receiver's result by one round).
    if (!found) found = slot_ref(receiver, tag, payload);
    if (!found) return;
    member_chain_root_ref_tag[member] = tag;
    member_chain_root_ref_payload[member] = payload;
}
