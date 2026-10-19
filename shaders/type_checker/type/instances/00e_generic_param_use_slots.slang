// HIR-derived generic parameter use slots.
//
// Declaration identity and lexical slot composition are shared with body
// replay. Each scope uses the exact (owner, name) parameter index; enclosing
// scopes supply earlier slots in separate type and constant domains.

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
StructuredBuffer<uint> language_name_id;
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
StructuredBuffer<uint> interface_public_decl_index_by_hir;

RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM = 2u;
static const uint HIR_TYPE = 5u;
static const uint HIR_IMPL = 35u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint LANGUAGE_SYMBOL_SELF = 72u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;

static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_SCALAR = 1u;
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

#include "lexical_parameter_slots.slang"

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

void publish_type_parameter_reference(uint row, uint slot, uint use_token)
{
    type_generic_param_slot_by_token[use_token] = slot;
    uint tag = TYPE_REF_GENERIC_PARAM;
    uint payload = generic_param_token[row];
    type_expr_ref_tag[use_token] = tag;
    type_expr_ref_payload[use_token] = payload;
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

    uint use_token = compact_hir_core[payload.type_node].token_start;
    uint parameter = lexical_parameter_row(variant.owner, use_token, GENERIC_PARAM_KIND_TYPE);
    uint slot = lexical_parameter_slot(parameter);
    if (slot != INVALID) publish_type_parameter_reference(parameter, slot, use_token);
}

void publish_decl_generic_param_slot(uint row)
{
    if (!valid_row(row))
        return;

    uint token = generic_param_token[row];
    if (!valid_token(token))
        return;

    uint slot = lexical_parameter_slot(row);
    if (slot == INVALID)
        return;
    // Declaration publication owns the domain bound. Reject here before a
    // later structural reader can misclassify an out-of-range parameter as
    // an unknown type, including parameters not used by any call.
    if (slot >= 32u)
    {
        record_min_token_error(status, token, ERR_BAD_HIR, 0x474e0002u);
        return;
    }

    uint kind = generic_param_kind[row];
    if (kind == GENERIC_PARAM_KIND_TYPE)
        type_generic_param_slot_by_token[token] = slot;
    else if (kind == GENERIC_PARAM_KIND_CONST)
        type_const_param_slot_by_token[token] = slot;
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

    uint row = lexical_parameter_row(node, token, GENERIC_PARAM_KIND_CONST);
    if (row == INVALID)
        return;

    uint slot = lexical_parameter_slot(row);
    if (slot != INVALID)
        type_const_param_slot_by_token[token] = slot;
}

// The trait item whose declaration encloses `node`, or INVALID (an impl, or
// no trait, encloses it first).
uint enclosing_trait(uint node)
{
    uint hir_count = active_hir_node_count();
    for (uint depth = 0u; depth < 64u && node < hir_count; depth++)
    {
        HirCore core = compact_hir_core[node];
        if (core.kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT) return node;
        if (core.kind == HIR_IMPL || core.parent == node) return INVALID;
        node = core.parent;
    }
    return INVALID;
}

// `Self` in a trait declaration names the implementing type. It is one
// implicit type parameter of the trait, in the slot after the trait's declared
// type parameters, so a bound's subject (methods/07a) and an impl's subject
// (predicates/method_validation_common.slang) bind it as they bind the
// declared ones. Its identity is the trait's name token; it has no generic
// parameter row and adds to no parameter count.
void publish_trait_self_reference(uint node, uint token)
{
    uint name = name_id_by_token[token];
    if (name == INVALID || name != language_name_id[LANGUAGE_SYMBOL_SELF]) return;
    uint trait = enclosing_trait(node);
    if (trait == INVALID) return;
    uint owner = hir_generic_owner_token(compact_hir_core[trait], compact_hir_payload[trait], gParams.n_tokens);
    if (!valid_token(owner)) return;
    uint slot = type_decl_generic_param_count_by_owner_token[owner];
    if (slot >= 32u)
    {
        record_min_token_error(status, token, ERR_BAD_HIR, 0x474e0002u);
        return;
    }
    type_generic_param_slot_by_token[owner] = slot;
    type_generic_param_slot_by_token[token] = slot;
    type_expr_ref_tag[token] = TYPE_REF_GENERIC_PARAM;
    type_expr_ref_payload[token] = owner;
    // The identity token reads like a parameter's declaration token: a
    // declaration return of `Self` names it as the return type token
    // (calls/02_functions), and semantic/artifact/00_calls reads its
    // reference there.
    type_expr_ref_tag[owner] = TYPE_REF_GENERIC_PARAM;
    type_expr_ref_payload[owner] = owner;
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

    // A path `P::member` whose first segment is a lexical type parameter
    // names an associated member of that parameter: its qualifier is a type
    // use, which method lookup reads as the call's receiver (methods/06). A
    // path span ends after its leaf, so a qualified path spans more than one
    // token.
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    bool qualified_value = node < hir_count && compact_hir_core[node].kind == HIR_PATH_EXPR &&
        compact_hir_core[node].token_end > compact_hir_core[node].token_start + 1u;
    if (node >= hir_count || (!qualified_value && (compact_hir_core[node].kind != HIR_TYPE ||
        compact_hir_payload[node].a != HIR_TYPE_FORM_PATH)))
        return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return;

    uint row = lexical_parameter_row(node, token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
    {
        if (!qualified_value) publish_trait_self_reference(node, token);
        return;
    }

    uint slot = lexical_parameter_slot(row);
    if (slot != INVALID)
    {
        publish_type_parameter_reference(row, slot, token);
    }
}
