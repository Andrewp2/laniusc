// HIR-driven array/slice details and reference forwarding.
//
// This pass runs after scalar/path refs, named instances, and aggregate headers
// are present. It attaches element refs and array length records, and forwards
// reference type nodes to their child type refs.

import hir_records;

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
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> module_type_path_type;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

static const uint TY_UNKNOWN = 0u;

static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint TYPE_LEN_UNSUPPORTED = 3u;
static const uint TYPE_LEN_LITERAL = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint projected_type_for_type_node(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint token = compact_hir_core[node].token_start;
    if (valid_token(token))
    {
        uint projected = module_type_path_type[token];
        if (projected != TY_UNKNOWN)
            return projected;
    }

    uint path = path_id_by_owner_hir[node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    uint segment_count = path < path_count ? path_segment_count[path] : 0u;
    uint segment = segment_count == 0u ? INVALID : path_segment_base[path] + segment_count - 1u;
    uint leaf_token = segment < gParams.n_tokens ? path_segment_token[segment] : INVALID;
    if (valid_token(leaf_token))
    {
        uint projected = module_type_path_type[leaf_token];
        if (projected != TY_UNKNOWN)
            return projected;
    }

    return TY_UNKNOWN;
}

bool child_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_ERROR;
    payload = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    if (!valid_node(node))
        return false;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return false;
    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_INVALID || tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_ERROR)
    {
        uint projected = projected_type_for_type_node(node);
        if (projected != TY_UNKNOWN)
        {
            tag = TYPE_REF_SCALAR;
            payload = projected;
        }
    }
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR;
}

void publish_array_or_slice_details(uint node, uint token, bool is_array)
{
    uint elem_tag = TYPE_REF_INVALID;
    uint elem_payload = INVALID;
    HirPayload type = compact_hir_payload[node];
    bool ok = child_ref(type.b, elem_tag, elem_payload);

    type_instance_elem_ref_tag[token] = ok ? elem_tag : TYPE_REF_ERROR;
    type_instance_elem_ref_payload[token] = ok ? elem_payload : token;
    type_instance_state[token] = ok ? TYPE_INSTANCE_RESOLVED : TYPE_INSTANCE_UNSUPPORTED;

    if (!is_array)
        return;

    uint len_token = type.c;
    if (!valid_token(len_token))
    {
        type_instance_len_kind[token] = TYPE_LEN_UNSUPPORTED;
        type_instance_len_payload[token] = token;
    }
    else
    {
        uint len_value = type.d;
        if (len_value != INVALID)
        {
            type_instance_len_kind[token] = TYPE_LEN_LITERAL;
            type_instance_len_payload[token] = len_value;
        }
        else
        {
            type_instance_len_kind[token] = TYPE_LEN_CONST_PARAM;
            type_instance_len_payload[token] = len_token;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_TYPE)
        return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return;

    HirPayload type = compact_hir_payload[node];
    uint form = type.a;
    if (form == HIR_TYPE_FORM_ARRAY || form == HIR_TYPE_FORM_SLICE)
    {
        publish_array_or_slice_details(node, token, form == HIR_TYPE_FORM_ARRAY);
        return;
    }

    if (form == HIR_TYPE_FORM_REF)
    {
        uint tag = TYPE_REF_INVALID;
        uint payload = INVALID;
        if (child_ref(type.b, tag, payload))
        {
            type_expr_ref_tag[token] = tag;
            type_expr_ref_payload[token] = payload;
        }
        else
        {
            type_expr_ref_tag[token] = TYPE_REF_ERROR;
            type_expr_ref_payload[token] = token;
        }
    }
}
