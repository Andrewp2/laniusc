// Scatter HIR-derived declaration generic-parameter records.
//
// Scheduling contract:
// - Dispatch after type_check_type_instances_00a_mark_generic_param_records and
//   a counted prefix scan over generic_param_flag.
// - Each generic/const parameter declaration writes one compact row. Later
//   passes sort those rows for duplicate-name validation and name lookup.
// - This pass does not scan declaration subtrees.

import generated_parse_production_ids;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_param_flag;
StructuredBuffer<uint> generic_param_prefix;
StructuredBuffer<uint> generic_decl_owner_by_node;

RWStructuredBuffer<uint> type_decl_generic_param_count;
RWStructuredBuffer<uint> type_decl_generic_param_count_by_node;
RWStructuredBuffer<uint> type_decl_const_param_count_by_node;
RWStructuredBuffer<uint> generic_param_owner_node;
RWStructuredBuffer<uint> generic_param_name_id;
RWStructuredBuffer<uint> generic_param_token;
RWStructuredBuffer<uint> generic_param_node;
RWStructuredBuffer<uint> generic_param_kind;
RWStructuredBuffer<uint> generic_param_key_order;
RWStructuredBuffer<uint> generic_param_slot_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool is_generic_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_TYPE_PARAM;
}

bool simple_impl_generic_param_list_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_ENUM_TYPE_PARAMS_SOME ||
           kind == PROD_ENUM_TYPE_PARAMS_MORE;
}

bool const_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_CONST_PARAM;
}

uint const_param_name_token(uint node)
{
    uint token = valid_node(node) ? hir_token_pos[node] : INVALID;
    if (token == INVALID)
        return INVALID;
    return valid_token(token + 1u) ? token + 1u : INVALID;
}

uint param_name_token(uint node)
{
    if (is_generic_param_node(node))
        return hir_token_pos[node];
    if (simple_impl_generic_param_list_node(node))
        return hir_token_pos[node] + 1u;
    if (const_param_node(node))
        return const_param_name_token(node);
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || generic_param_flag[node] == 0u)
        return;

    uint row = generic_param_prefix[node];
    if (row >= gParams.n_tokens)
        return;

    uint decl_node = generic_decl_owner_by_node[node];
    if (!valid_node(decl_node))
        return;

    bool is_const = const_param_node(node);
    uint token = param_name_token(node);
    uint name_id = valid_token(token) ? name_id_by_token[token] : INVALID;

    generic_param_owner_node[row] = decl_node;
    generic_param_name_id[row] = name_id;
    generic_param_token[row] = token;
    generic_param_node[row] = node;
    generic_param_kind[row] = is_const ? GENERIC_PARAM_KIND_CONST : GENERIC_PARAM_KIND_TYPE;
    generic_param_key_order[row] = row;
    generic_param_slot_order[row] = row;

    if (is_const)
    {
        atomic_u32_add(type_decl_const_param_count_by_node, decl_node, 1u);
        return;
    }

    uint decl_name_token = hir_item_name_token[decl_node];
    uint decl_head_token = hir_token_pos[decl_node];
    atomic_u32_add(type_decl_generic_param_count_by_node, decl_node, 1u);
    if (valid_token(decl_name_token))
        atomic_u32_add(type_decl_generic_param_count, decl_name_token, 1u);
    if (valid_token(decl_head_token))
        atomic_u32_add(type_decl_generic_param_count, decl_head_token, 1u);
}
