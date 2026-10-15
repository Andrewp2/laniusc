import semantic_interface_layout;
import type_checker.mutable_checked_type_graph;
import type_checker.checked_index_reference;
import type_checker.substitution.ct_scoped;
// HIR member field result projection.
//
// The preceding member-receiver pass records the initial receiver type for
// every member-chain root and links consecutive member nodes. One lane owns
// each independent chain and carries the exact result ref through sorted
// (struct, field-name) lookups. Generic fields are substituted before the next
// transition, so layout and result types remain receiver-dependent at every
// depth without token rescans or fixed retry counts.

import hir_records;
import status;
import type_checker.type.instances.struct_field_lookup;
import type_checker.dependencies.record_fields;

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
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_field_lookup_state;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> member_next_node;
StructuredBuffer<uint> member_chain_root_ref_tag;
StructuredBuffer<uint> member_chain_root_ref_payload;

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_STRUCT_BASE = 4096u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

bool valid_compact_field(uint row)
{
    return row != INVALID && row < active_compact_field_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint scalar_struct_decl_token(uint payload)
{
    // Struct scalar codes are source-token addressed. Do not impose the old
    // 2,048-token interval here: validate the decoded declaration against the
    // compact HIR item kind in struct_node_for_decl_token instead.
    if (payload >= TY_STRUCT_BASE)
        return payload - TY_STRUCT_BASE;
    return INVALID;
}

uint receiver_decl_token(uint tag, uint payload)
{
    if (tag == TYPE_REF_INSTANCE && payload < mutable_type_capacity())
    {
        uint decl_token = type_instance_decl_token[payload];
        return valid_token(decl_token) ? decl_token : INVALID;
    }
    if (tag == TYPE_REF_SCALAR)
        return scalar_struct_decl_token(payload);
    return INVALID;
}

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    uint node = type_decl_hir_node_by_token[decl_token];
    if (valid_compact_node(node) && compact_hir_core[node].kind == HIR_STRUCT_ITEM)
        return node;
    return INVALID;
}

uint field_row_for_member(uint struct_node, uint member_token)
{
    if (!valid_compact_node(struct_node) || !valid_token(member_token))
        return INVALID;

    uint name_id = name_id_by_token[member_token];
    if (name_id == INVALID)
        return INVALID;

    uint field_row = struct_field_lookup_find(
        struct_node, name_id, active_compact_field_count(), gParams.n_tokens,
        compact_fields, name_id_by_token, struct_field_lookup_state);
    return valid_compact_field(field_row) ? field_row : INVALID;
}

uint ordinal_for_field_row(uint struct_node, uint field_row)
{
    if (!valid_compact_node(struct_node) || !valid_compact_field(field_row))
        return INVALID;
    return compact_fields[field_row].owner == struct_node
               ? compact_fields[field_row].ordinal
               : INVALID;
}

uint type_head_token_for_compact_node(uint type_node)
{
    if (!valid_compact_node(type_node))
        return INVALID;
    uint owner = compact_hir_core[type_node].token_start;
    uint path_i = path_id_by_owner_hir[type_node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path_i != INVALID && path_i < path_count)
    {
        uint count = path_segment_count[path_i];
        if (count != 0u)
        {
            uint row = path_segment_base[path_i] + count - 1u;
            uint leaf = row < gParams.n_tokens ? path_segment_token[row] : INVALID;
            if (valid_token(leaf) &&
                type_expr_ref_tag[leaf] != TYPE_REF_INVALID)
                return leaf;
        }
    }
    return valid_token(owner) ? owner : INVALID;
}

bool member_expr_is_call_callee(uint node)
{
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_MEMBER_EXPR)
        return false;
    uint call_node = compact_hir_expr_parent[node];
    return valid_node(call_node) &&
           compact_hir_core[call_node].kind == HIR_CALL_EXPR &&
           compact_hir_payload[call_node].a == node;
}

void publish_member_field_chain_for_root(uint member_node)
{
    if (!valid_node(member_node) || (compact_hir_core[member_node].kind != HIR_MEMBER_EXPR &&
        compact_hir_core[member_node].kind != HIR_INDEX_EXPR))
        return;
    if (member_expr_is_call_callee(member_node))
        return;

    uint receiver_node = compact_hir_payload[member_node].b;
    if (valid_node(receiver_node) && (compact_hir_core[receiver_node].kind == HIR_MEMBER_EXPR ||
        compact_hir_core[receiver_node].kind == HIR_INDEX_EXPR))
        return;
    uint receiver_tag = member_chain_root_ref_tag[member_node];
    uint receiver_payload = member_chain_root_ref_payload[member_node];
    if (receiver_tag == TYPE_REF_INVALID || receiver_payload == INVALID)
        return;

    uint steps = 0u;
    while (valid_node(member_node) &&
           steps < active_hir_node_count())
    {
        uint kind = compact_hir_core[member_node].kind;
        if (kind == HIR_INDEX_EXPR)
        {
            // Index lookup follows reference layers in the carried receiver,
            // without replacing the source value's complete reference type.
            uint instance;
            if (!checked_index_container<MutableCheckedTypeGraph>(receiver_tag, receiver_payload,
                mutable_type_capacity(), instance)) return;
            receiver_tag = type_instance_elem_ref_tag[instance];
            receiver_payload = type_instance_elem_ref_payload[instance];
            member_node = member_next_node[member_node];
            steps += 1u;
            continue;
        }
        if (kind != HIR_MEMBER_EXPR) return;
        uint member_token = compact_hir_payload[member_node].c;
        if (!valid_token(member_token) || member_expr_is_call_callee(member_node))
            return;

        // Receiver initialization is a traversal input, not the field's
        // result type. A failed lookup must not leave the receiver masquerading
        // as a selected value in return or argument checking.
        member_result_ref_tag[member_token] = TYPE_REF_INVALID;
        member_result_ref_payload[member_token] = INVALID;
        member_result_context_instance[member_token] = INVALID;
        member_result_field_ordinal[member_token] = INVALID;
        member_result_field_node[member_token] = INVALID;

        // Member selection automatically dereferences references. The value
        // still carries its reference type; only lookup uses the referent.
        for (uint depth = 0u; depth < 64u && receiver_tag == TYPE_REF_INSTANCE &&
             receiver_payload < mutable_type_capacity() &&
             type_instance_kind[receiver_payload] == 4u; depth++)
        {
            uint referent = receiver_payload;
            receiver_tag = type_instance_elem_ref_tag[referent];
            receiver_payload = type_instance_elem_ref_payload[referent];
        }
        uint context_instance = receiver_tag == TYPE_REF_INSTANCE && (receiver_payload < mutable_type_capacity())
            ? receiver_payload
            : INVALID;
        uint tag = TYPE_REF_INVALID; uint payload = INVALID;
        uint ordinal = INVALID; uint field_token = INVALID;
        bool already_projected = false;
        uint decl_token = receiver_decl_token(receiver_tag, receiver_payload);
        if (valid_token(decl_token))
        {
            uint struct_node = struct_node_for_decl_token(decl_token);
            uint field_row = field_row_for_member(struct_node, member_token);
            if (!valid_compact_field(field_row))
            { record_min_token_error(status, member_token, 8u, 0u); return; }
            HirField field = compact_fields[field_row];
            uint type_token = type_head_token_for_compact_node(field.value);
            if (!valid_token(type_token))
                return;
            tag = type_expr_ref_tag[type_token];
            payload = type_expr_ref_payload[type_token];
            if (tag == TYPE_REF_GENERIC_PARAM)
            {
                if (!valid_token(payload)) return;
                uint slot = type_generic_param_slot_by_token[payload];
                if (slot == INVALID || context_instance == INVALID ||
                    !MutableCheckedTypeGraph.environment_argument(context_instance, slot, tag, payload)) return;
                already_projected = true;
            }
            ordinal = ordinal_for_field_row(struct_node, field_row);
            field_token = field.name_token;
        }
        else
        {
            uint name = name_id_by_token[member_token];
            if (context_instance == INVALID || name >= gParams.n_tokens) return;
            ordinal = imported_record_field_ordinal(context_instance,
                name_hash_lo[name], name_hash_hi[name]);
            if (ordinal == INVALID)
            {
                if (imported_record_fields_available(context_instance))
                    record_min_token_error(status, member_token, 8u, 0u);
                return;
            }
            if (!imported_record_field_type(context_instance, ordinal, tag, payload)) return;
            already_projected = true;
        }

        if (tag == TYPE_REF_INVALID || payload == INVALID) return;

        // A field type written in the receiver declaration's scope is
        // substituted under the receiver application (canonical IDs).
        uint failure = 0u;
        if (tag == TYPE_REF_INSTANCE && !ct_scoped_reference(
            tag, payload, already_projected ? INVALID : context_instance, gParams.n_tokens,
            tag, payload, failure))
        {
            record_min_token_error(status, member_token, 3u, failure);
            return;
        }

        member_result_context_instance[member_token] = context_instance;
        member_result_field_ordinal[member_token] = ordinal;
        // The backend-facing artifact carries a stable source-token identity,
        // never a raw parser row.
        member_result_field_node[member_token] = field_token;
        member_result_ref_tag[member_token] = tag;
        member_result_ref_payload[member_token] = payload;

        receiver_tag = tag;
        receiver_payload = payload;
        member_node = member_next_node[member_node];
        steps += 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    publish_member_field_chain_for_root(node);
}
