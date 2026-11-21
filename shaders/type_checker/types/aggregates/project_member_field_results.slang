import shared.semantics.semantic_interface_layout;
import type_checker.checked_types.mutable_checked_type_graph;
import type_checker.constants.constant_atoms_identity;
import type_checker.concrete_types.concrete_type_closure;
import type_checker.checked_types.checked_index_reference;
import type_checker.substitution.scoped_reference_substitution;
// One lane resolves a complete member/index chain. The receiver of the
// next link is the checked result of the current one, held in the lane.
// The worklist contains only links with valid member tokens and excludes call callees.
import shared.syntax.hir_records;
import shared.buffers.status;
import type_checker.types.aggregates.struct_field_lookup;
import type_checker.dependencies.record_fields;
import type_checker.calls.inference_activity;

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

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
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
StructuredBuffer<uint> member_chain_roots;
StructuredBuffer<uint> aggregate_root_counts;
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
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TRY_EXPR = 36u;
static const uint NAME_ROLE_SELF = 1u;
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

uint name_token(uint node)
{
    if (!valid_node(node)) return INVALID;
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
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_CALL_EXPR) return false;
    tag = call_inference_result_tag[node]; payload = call_inference_result_payload[node];
    if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
    uint instance = call_result_instance[node];
    if (concrete_instance_is_closed<MutableCheckedTypeGraph, CheckedSourceConstantGraph,
        CheckedSourceConstantEnvironment>(instance, mutable_type_capacity(),
            checked_source_constant_parameter_capacity()))
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
    if (!valid_node(receiver) || compact_hir_core[receiver].kind != HIR_NAME_EXPR ||
        compact_hir_payload[receiver].b != NAME_ROLE_SELF) return false;
    uint fn = compact_hir_nearest_fn[member];
    if (!valid_node(fn)) return false;
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
    if (!valid_node(node)) return false;
    // A try can publish its payload after expression projection. An
    // argument-free local nominal is complete at its question-mark token,
    // so the member pass can use that type before the projected slot catches up.
    HirCore core = compact_hir_core[node];
    if (core.kind == HIR_TRY_EXPR && call_inference_round[0u] != 0u &&
        core.token_end != 0u && valid_token(core.token_end - 1u))
    {
        uint token = core.token_end - 1u;
        uint row = decl_type_ref_payload[token];
        if (decl_type_ref_tag[token] == TYPE_REF_INSTANCE && row < mutable_type_capacity() &&
            type_instance_kind[row] == 1u && type_instance_arg_count[row] == 0u &&
            valid_token(type_instance_decl_token[row]))
        {
            tag = TYPE_REF_INSTANCE;
            payload = row;
            return true;
        }
    }
    tag = call_inference_result_tag[node]; payload = call_inference_result_payload[node];
    if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
    tag = TYPE_REF_INVALID; payload = INVALID;
    return false;
}

bool seed_receiver(uint node, out uint tag, out uint payload)
{
    uint kind = compact_hir_core[node].kind;
    HirPayload p = compact_hir_payload[node];
    uint receiver = p.b;
    uint token = kind == HIR_MEMBER_EXPR && valid_token(p.d) ? p.d : name_token(receiver);
    if (call_ref(receiver, tag, payload) || value_ref(token, tag, payload)) return true;
    if (kind == HIR_MEMBER_EXPR && self_ref(node, tag, payload)) return true;
    uint receiver_name = name_token(receiver);
    if (receiver_name != token && value_ref(receiver_name, tag, payload)) return true;
    return slot_ref(receiver, tag, payload);
}

void clear_member_result(uint token)
{
    member_result_ref_tag[token] = TYPE_REF_INVALID;
    member_result_ref_payload[token] = INVALID;
    member_result_context_instance[token] = INVALID;
    member_result_field_ordinal[token] = INVALID;
    member_result_field_node[token] = INVALID;
}

void publish_visible_member_type(uint token, uint tag, uint payload)
{
    uint ty = 0u;
    if (tag == TYPE_REF_SCALAR)
        ty = payload;
    else if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : payload;
        if (slot != INVALID) ty = 8192u + slot;
    }
    else if (tag == TYPE_REF_INSTANCE)
    {
        uint kind = payload < mutable_type_capacity() ? type_instance_kind[payload] : 0u;
        if (kind < 1u || kind > 4u)
        {
            record_min_token_error(status, token, 3u, 0u);
            return;
        }
        if (valid_token(payload)) ty = visible_type[payload];
    }
    if (ty != 0u) visible_type[token] = ty;
}

void resolve_member_chain(inout uint member_node, uint receiver_tag, uint receiver_payload)
{
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
        publish_visible_member_type(member_token, tag, payload);

        receiver_tag = tag;
        receiver_payload = payload;
        member_node = member_next_node[member_node];
        steps += 1u;
    }
}

#include "member_chain_workgroup.slang"

[shader("compute")]
[numthreads(MEMBER_CHAIN_WORKGROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    if (local.x % MEMBER_CHAIN_LANES != 0u) return;
    uint lane = (group.x + group.y * 65535u) * MEMBER_CHAINS_PER_WORKGROUP
        + local.x / MEMBER_CHAIN_LANES;
    if (lane >= aggregate_root_counts[0u]) return;
    uint node = member_chain_roots[lane];
    HirCore core = compact_hir_core[node];
    if (core.kind == HIR_INDEX_EXPR && member_next_node[node] == INVALID) return;
    if (!inference_item_active(core.token_start)) return;

    uint tag; uint payload;
    if (seed_receiver(node, tag, payload)) resolve_member_chain(node, tag, payload);

    // A failed receiver or lookup invalidates every unresolved link. The
    // chain's links share its enclosing function and inference activity.
    for (uint steps = 0u; valid_node(node) && steps < active_hir_node_count(); steps++)
    {
        if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
            clear_member_result(compact_hir_payload[node].c);
        node = member_next_node[node];
    }
}
