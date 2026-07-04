// HIR-derived generic parameter use slots.
//
// Declaration parameters are compacted and sorted before this pass. Use sites
// resolve their nearest generic declaration owner, then perform a bounded
// binary search over the sorted compact rows keyed by (owner declaration,
// interned name id). This avoids scanning declaration subtrees for every use.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_nearest_fn_node;
StructuredBuffer<uint> hir_method_impl_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> type_decl_const_param_count_by_node;
StructuredBuffer<uint> generic_decl_owner_by_node;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_node;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
StructuredBuffer<uint> generic_param_slot_order;

RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;

static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint GENERIC_STATUS_DUPLICATE_PARAM = 21u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_row(uint row)
{
    return row != INVALID && row < active_generic_param_count();
}

bool decl_has_generic_params(uint decl_node)
{
    return valid_node(decl_node) &&
           (type_decl_generic_param_count_by_node[decl_node] != 0u ||
            type_decl_const_param_count_by_node[decl_node] != 0u);
}

uint generic_decl_scope_for_type_node(uint node)
{
    uint decl_node = generic_decl_owner_by_node[node];
    if (valid_node(decl_node) && decl_has_generic_params(decl_node))
        return decl_node;

    uint fn_node = valid_node(node) ? hir_nearest_fn_node[node] : INVALID;
    uint impl_node = valid_node(fn_node) ? hir_method_impl_node[fn_node] : INVALID;
    return valid_node(impl_node) && decl_has_generic_params(impl_node)
        ? impl_node
        : decl_node;
}

bool generic_param_key_less(uint row, uint owner, uint name_id)
{
    uint row_owner = generic_param_owner_node[row];
    if (row_owner != owner)
        return row_owner < owner;
    return generic_param_name_id[row] < name_id;
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_node[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

bool same_duplicate_key(uint left, uint right)
{
    if (!valid_row(left) || !valid_row(right))
        return false;
    if (generic_param_token[left] == generic_param_token[right])
        return false;
    uint owner = generic_param_owner_node[right];
    uint name = generic_param_name_id[right];
    return owner != INVALID &&
           name != INVALID &&
           generic_param_owner_node[left] == owner &&
           generic_param_name_id[left] == name;
}

void validate_duplicate_generic_param_key(uint sorted_i)
{
    if (sorted_i == 0u || sorted_i >= active_generic_param_count())
        return;

    uint row = generic_param_key_order[sorted_i];
    uint previous = generic_param_key_order[sorted_i - 1u];
    if (!same_duplicate_key(previous, row))
        return;

    uint token = generic_param_token[row];
    if (valid_token(token))
        record_min_token_error(status, token, ERR_BAD_HIR, GENERIC_STATUS_DUPLICATE_PARAM);
}

bool generic_param_slot_key_less(uint row, uint owner, uint kind, uint node)
{
    if (!valid_row(row))
        return false;

    uint row_owner = generic_param_owner_node[row];
    if (row_owner != owner)
        return row_owner < owner;
    uint row_kind = generic_param_kind[row];
    if (row_kind != kind)
        return row_kind < kind;
    return generic_param_node[row] < node;
}

bool generic_param_slot_segment_matches(uint row, uint owner, uint kind)
{
    return valid_row(row) &&
           generic_param_owner_node[row] == owner &&
           generic_param_kind[row] == kind;
}

uint generic_param_slot_segment_start(uint owner, uint kind)
{
    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_slot_order[mid];
        if (row >= count || !generic_param_slot_key_less(row, owner, kind, 0u))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;
    uint row = generic_param_slot_order[lo];
    return generic_param_slot_segment_matches(row, owner, kind) ? lo : INVALID;
}

uint generic_param_slot_order_index_for_row(uint row)
{
    if (!valid_row(row))
        return INVALID;

    uint owner = generic_param_owner_node[row];
    uint kind = generic_param_kind[row];
    uint node = generic_param_node[row];
    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_row = generic_param_slot_order[mid];
        if (mid_row >= count || !generic_param_slot_key_less(mid_row, owner, kind, node))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count || generic_param_slot_order[lo] != row)
        return INVALID;
    return lo;
}

uint generic_param_slot_from_order_index(uint sorted_i)
{
    if (sorted_i >= active_generic_param_count())
        return INVALID;

    uint row = generic_param_slot_order[sorted_i];
    if (!valid_row(row))
        return INVALID;

    uint owner = generic_param_owner_node[row];
    uint kind = generic_param_kind[row];
    uint start = generic_param_slot_segment_start(owner, kind);
    if (start == INVALID || sorted_i < start)
        return INVALID;

    uint slot = sorted_i - start;
    uint count = kind == GENERIC_PARAM_KIND_CONST
        ? type_decl_const_param_count_by_node[owner]
        : type_decl_generic_param_count_by_node[owner];
    return slot < count ? slot : INVALID;
}

uint slot_for_row(uint row)
{
    if (!valid_row(row))
        return INVALID;

    uint sorted_i = generic_param_slot_order_index_for_row(row);
    return sorted_i == INVALID ? INVALID : generic_param_slot_from_order_index(sorted_i);
}

void publish_decl_generic_param_slot(uint sorted_i)
{
    if (sorted_i >= active_generic_param_count())
        return;

    uint row = generic_param_slot_order[sorted_i];
    if (!valid_row(row))
        return;

    uint token = generic_param_token[row];
    if (!valid_token(token))
        return;

    uint slot = generic_param_slot_from_order_index(sorted_i);
    if (slot == INVALID)
        return;

    uint kind = generic_param_kind[row];
    if (kind == GENERIC_PARAM_KIND_TYPE)
        type_generic_param_slot_by_token[token] = slot;
    else if (kind == GENERIC_PARAM_KIND_CONST)
        type_const_param_slot_by_token[token] = slot;
}

uint generic_param_row_for_name(uint decl_node, uint name_token, uint kind)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_key_order[mid];
        if (row >= count || !generic_param_key_less(row, decl_node, name_id))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;
    uint row = generic_param_key_order[lo];
    return generic_param_key_matches(row, decl_node, name_id, kind) ? row : INVALID;
}

void publish_const_len_use_slot(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] != HIR_TYPE_FORM_ARRAY)
        return;

    uint token = hir_type_len_token[node];
    if (!valid_token(token))
        return;

    uint decl_node = generic_decl_scope_for_type_node(node);
    if (!valid_node(decl_node) || !decl_has_generic_params(decl_node) ||
        type_decl_const_param_count_by_node[decl_node] == 0u)
        return;

    uint row = generic_param_row_for_name(decl_node, token, GENERIC_PARAM_KIND_CONST);
    if (row == INVALID)
        return;

    uint slot = slot_for_row(row);
    if (slot != INVALID)
        type_const_param_slot_by_token[token] = slot;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    validate_duplicate_generic_param_key(node);
    publish_decl_generic_param_slot(node);
    publish_const_len_use_slot(node);

    if (!valid_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] != HIR_TYPE_FORM_PATH)
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return;

    uint decl_node = generic_decl_scope_for_type_node(node);
    if (!valid_node(decl_node) || !decl_has_generic_params(decl_node) ||
        type_decl_generic_param_count_by_node[decl_node] == 0u)
        return;

    uint row = generic_param_row_for_name(decl_node, token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
        return;

    uint slot = slot_for_row(row);
    if (slot != INVALID)
        type_generic_param_slot_by_token[token] = slot;
}
