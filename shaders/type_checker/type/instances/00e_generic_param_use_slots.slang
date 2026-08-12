// HIR-derived generic parameter use slots.
//
// Declaration parameters are compacted and sorted before this pass. Use sites
// resolve their nearest generic declaration owner, then perform a bounded
// binary search over the sorted compact rows keyed by (owner declaration,
// interned name id). This avoids scanning declaration subtrees for every use.

import hir_records;
import status;
import type_checker.type.instances.generic_param_lookup;

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
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> generic_type_param_prefix;
StructuredBuffer<uint> generic_const_param_prefix;

RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;

static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint GENERIC_STATUS_DUPLICATE_PARAM = 21u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
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

uint generic_owner_token(uint decl_node)
{
    if (!valid_node(decl_node))
        return INVALID;
    uint name_token = compact_hir_payload[decl_node].b;
    return valid_token(name_token) ? name_token : compact_hir_core[decl_node].token_start;
}

bool owner_has_generic_params(uint owner_token)
{
    return valid_token(owner_token) &&
           (type_decl_generic_param_count_by_owner_token[owner_token] != 0u ||
            type_decl_const_param_count_by_owner_token[owner_token] != 0u);
}

uint generic_decl_scope_token_for_type_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    return generic_owner_token(generic_decl_owner_by_node_a[node]);
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_token[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

void validate_duplicate_generic_param_key(uint row)
{
    uint count = active_generic_param_count();
    if (row >= count)
        return;
    uint representative = generic_param_lookup_find(
        generic_param_owner_token[row], generic_param_name_id[row],
        count, gParams.n_tokens,
        generic_param_owner_token, generic_param_name_id,
        generic_param_lookup_state);
    if (representative == INVALID || representative == row ||
        generic_param_token[representative] == generic_param_token[row])
        return;

    uint token = generic_param_token[row];
    if (valid_token(token))
        record_min_token_error(status, token, ERR_BAD_HIR, GENERIC_STATUS_DUPLICATE_PARAM);
}

uint slot_for_row(uint row)
{
    if (!valid_row(row))
        return INVALID;
    HirGenericParam parameter = compact_generic_params[row];
    if (!valid_node(parameter.owner))
        return INVALID;
    HirRange range = compact_generic_param_ranges[parameter.owner];
    if (range.count == 0u || range.start == INVALID ||
        row < range.start || row >= range.start + range.count)
        return INVALID;
    uint kind = generic_param_kind[row];
    return kind == GENERIC_PARAM_KIND_CONST
        ? generic_const_param_prefix[row] - generic_const_param_prefix[range.start]
        : generic_type_param_prefix[row] - generic_type_param_prefix[range.start];
}

void publish_generic_type_use_for_owner(uint owner_token, uint use_token)
{
    if (!valid_token(owner_token) || !valid_token(use_token) ||
        !owner_has_generic_params(owner_token))
        return;

    uint row = generic_param_row_for_name(
        owner_token,
        use_token,
        GENERIC_PARAM_KIND_TYPE);
    uint slot = slot_for_row(row);
    if (slot != INVALID)
    {
        type_generic_param_slot_by_token[use_token] = slot;
        type_expr_ref_tag[use_token] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload[use_token] = generic_param_token[row];
    }
}

void publish_compact_variant_payload_use_slot(uint row)
{
    uint payload_count = min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
    if (row >= payload_count)
        return;

    HirVariantPayload payload = compact_variant_payloads[row];
    uint variant_count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    if (payload.variant >= variant_count)
        return;
    HirVariant variant = compact_variants[payload.variant];

    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (variant.owner >= hir_count || payload.type_node >= hir_count)
        return;

    uint owner_token = compact_hir_payload[variant.owner].b;
    uint use_token = compact_hir_core[payload.type_node].token_start;
    publish_generic_type_use_for_owner(owner_token, use_token);
}

void publish_decl_generic_param_slot(uint row)
{
    if (!valid_row(row))
        return;

    uint token = generic_param_token[row];
    if (!valid_token(token))
        return;

    uint slot = slot_for_row(row);
    if (slot == INVALID)
        return;

    uint kind = generic_param_kind[row];
    if (kind == GENERIC_PARAM_KIND_TYPE)
        type_generic_param_slot_by_token[token] = slot;
    else if (kind == GENERIC_PARAM_KIND_CONST)
        type_const_param_slot_by_token[token] = slot;
}

uint generic_param_row_for_name(uint owner_token, uint name_token, uint kind)
{
    if (!valid_token(owner_token) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint row = generic_param_lookup_find(
        owner_token, name_id, count, gParams.n_tokens,
        generic_param_owner_token, generic_param_name_id,
        generic_param_lookup_state);
    return generic_param_key_matches(row, owner_token, name_id, kind) ? row : INVALID;
}

void publish_const_len_use_slot(uint node)
{
    if (!valid_node(node))
        return;

    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= hir_count || compact_hir_core[node].kind != HIR_TYPE ||
        compact_hir_payload[node].a != HIR_TYPE_FORM_ARRAY)
        return;

    uint token = compact_hir_payload[node].c;
    if (!valid_token(token))
        return;

    uint owner_token = generic_decl_scope_token_for_type_node(node);
    if (!owner_has_generic_params(owner_token) ||
        type_decl_const_param_count_by_owner_token[owner_token] == 0u)
        return;

    uint row = generic_param_row_for_name(owner_token, token, GENERIC_PARAM_KIND_CONST);
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
    publish_compact_variant_payload_use_slot(node);

    if (!valid_node(node))
        return;

    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= hir_count || compact_hir_core[node].kind != HIR_TYPE ||
        compact_hir_payload[node].a != HIR_TYPE_FORM_PATH)
        return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return;

    uint owner_token = generic_decl_scope_token_for_type_node(node);
    if (!owner_has_generic_params(owner_token) ||
        type_decl_generic_param_count_by_owner_token[owner_token] == 0u)
        return;

    uint row = generic_param_row_for_name(owner_token, token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
        return;

    uint slot = slot_for_row(row);
    if (slot != INVALID)
    {
        type_generic_param_slot_by_token[token] = slot;
        type_expr_ref_tag[token] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload[token] = generic_param_token[row];
    }
}
