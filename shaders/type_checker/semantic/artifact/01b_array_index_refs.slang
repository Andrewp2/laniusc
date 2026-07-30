// Project checked array/slice references into dense semantic HIR.
//
// The earlier index-result pass establishes that the index expression has a
// valid array/slice declaration and publishes its scalar cache. This final
// projection is entirely dense-HIR keyed: no raw parser row survives into the
// checked semantic artifact boundary.

import hir_records;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_array_length_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_FOR_STMT = 30u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint name_token(uint node)
{
    if (!valid_hir(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         compact_hir_core[node].kind != HIR_PATH_EXPR))
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : INVALID;
}

void publish_ref(uint node, uint tag, uint payload)
{
    if (!valid_hir(node)) return;
    semantic_expr_ref_tag_by_hir[node] = tag;
    semantic_expr_ref_payload_by_hir[node] = payload;
}

void publish_array_length(uint node, uint instance)
{
    if (!valid_hir(node) || type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return;
    semantic_array_length_by_hir[node] = type_instance_len_payload[instance];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint index_node = core.kind == HIR_INDEX_EXPR ? node : INVALID;
    bool for_node = core.kind == HIR_FOR_STMT;
    uint base_node = index_node != INVALID
        ? payload.b
        : for_node ? payload.c : node;
    uint token = name_token(base_node);
    uint decl = valid_token(token) ? visible_decl[token] : INVALID;
    if (!valid_token(decl) || decl_type_ref_tag[decl] != TYPE_REF_INSTANCE) return;

    uint instance = decl_type_ref_payload[decl];
    if (!valid_token(instance)) return;
    uint kind = type_instance_kind[instance];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE) return;

    uint elem_tag = type_instance_elem_ref_tag[instance];
    uint elem_payload = type_instance_elem_ref_payload[instance];
    if (elem_tag == TYPE_REF_INVALID || elem_payload == INVALID) return;

    publish_ref(base_node, TYPE_REF_INSTANCE, instance);
    if (kind == TYPE_INSTANCE_ARRAY)
    {
        publish_array_length(base_node, instance);
    }
    if (for_node)
    {
        publish_ref(node, elem_tag, elem_payload);
        if (kind == TYPE_INSTANCE_ARRAY) publish_array_length(node, instance);
    }
    if (index_node == INVALID) return;
    publish_ref(index_node, elem_tag, elem_payload);
}
