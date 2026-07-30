// Initialize dense-HIR member chains and their root receiver references.
import hir_records;
import gpu_index;

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
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;
RWStructuredBuffer<uint> member_next_node;

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

bool index_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_INDEX_EXPR) return false;
    uint token = name_token(compact_hir_payload[node].b);
    uint decl = valid_token(token) ? visible_decl[token] : INVALID;
    if (!valid_token(decl) || decl_type_ref_tag[decl] != TYPE_REF_INSTANCE) return false;
    uint instance = decl_type_ref_payload[decl];
    if (!valid_token(instance)) return false;
    uint kind = type_instance_kind[instance];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE) return false;
    tag = type_instance_elem_ref_tag[instance];
    payload = type_instance_elem_ref_payload[instance];
    return tag != TYPE_REF_INVALID && payload != INVALID;
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
    if (!valid_hir(member) || compact_hir_core[member].kind != HIR_MEMBER_EXPR) return;
    HirPayload p = compact_hir_payload[member];
    uint token = p.c;
    if (!valid_token(token)) return;
    member_result_ref_tag[token] = TYPE_REF_INVALID;
    member_result_ref_payload[token] = INVALID;
    member_result_context_instance[token] = INVALID;
    member_result_field_ordinal[token] = INVALID;
    member_result_field_node[token] = INVALID;

    uint receiver = p.b;
    if (valid_hir(receiver) && compact_hir_core[receiver].kind == HIR_MEMBER_EXPR)
    {
        uint previous;
        InterlockedCompareExchange(member_next_node[receiver], INVALID, member, previous);
        return;
    }
    if (call_callee(member)) return;

    uint tag; uint payload;
    uint receiver_token = valid_token(p.d) ? p.d : name_token(receiver);
    bool found = index_ref(receiver, tag, payload) || value_ref(receiver_token, tag, payload);
    if (!found) found = self_ref(member, tag, payload);
    if (!found) return;
    member_result_ref_tag[token] = tag;
    member_result_ref_payload[token] = payload;
    member_result_context_instance[token] =
        tag == TYPE_REF_INSTANCE && valid_token(payload) ? payload : INVALID;
}
