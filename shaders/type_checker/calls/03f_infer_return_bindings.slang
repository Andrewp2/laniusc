// Carry an expression's accepted complete type into an unannotated declaration.
// Initializers and result rows are immutable here; each statement owns its
// declaration, so name/index/member readers need no source-text inference.
// A `value?` expression owns its `?` token the same way: it publishes there
// the `Ok`/`Some` payload type of its `core::result::Result` or
// `core::option::Option` operand, after checking that the enclosing function
// returns the same enum with an identical error type.
//
// Types compare by canonical ID (docs/canonical-type-ids.md). A lane plans
// its declaration's new type, interns it and the published one on demand
// from one site, then validates, compares and publishes.
import hir_records;
import hir_expr_semantics;
import primitive_types;
import dependency_interface;
import type_checker.checked_type_graph;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
// Shares the candidate keys' decl_id_by_name_token binding.
import type_checker.canonical.canonical_candidates;
import type_checker.substitution.ct_checked;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
RWStructuredBuffer<uint> status;

void clear_unavailable_inferred_declaration(uint token)
{
    if (decl_type_ref_tag[token] == 0u && visible_type[token] == 0u) return;
    decl_type_ref_tag[token] = 0u;
    decl_type_ref_payload[token] = 0xffffffffu;
    visible_type[token] = 0u;
    uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
}

// A for statement owns its binder declaration. Sources are accepted expression
// facts from the preceding dispatch, including calls, fields and index results.
// The same pass runs on every dependency page; only the page containing an
// external nominal declaration may accept or reject that nominal iterable.
uint for_value_root(uint node, uint count)
{
    for (uint step = 0u; step < count && node < count; step++)
    {
        HirCore core = compact_hir_core[node];
        HirPayload value = compact_hir_payload[node];
        if (!hir_is_forward_expression(core.kind, value.a)) return node;
        if (value.b == node) return 0xffffffffu;
        node = value.b;
    }
    return 0xffffffffu;
}

uint named_for_range_kind(uint instance, out bool resident, out uint scalar)
{
    static const uint INVALID = 0xffffffffu;
    resident = true; scalar = 0u;
    if (instance >= checked_type_capacity() || type_instance_kind[instance] != 1u)
        return 0u;
    uint kind = 0u;
    uint library_id = external_type_library_id[instance];
    uint unit_id = external_type_unit_id[instance];
    uint local_id = external_type_local_index[instance];
    if (library_id != INVALID && unit_id != INVALID && local_id != INVALID)
    {
        uint declaration = dependency_find_declaration(library_id, unit_id, local_id);
        if (declaration == INVALID) { resident = false; return 0u; }
        uint base = declaration * 14u;
        uint module = dependency_declaration_word(base);
        if (module >= dependency_module_count()) return 0u;
        uint segment_base = dependency_module_word(module * 2u);
        uint segment_count = dependency_module_word(module * 2u + 1u);
        uint capacity = dependency_count(2u);
        if (segment_count != 2u || segment_base >= capacity || capacity - segment_base < 2u)
            return 0u;
        uint segments = segment_base * 4u;
        uint core_id = language_name_id[63u];
        uint range_module_id = language_name_id[64u];
        if (dependency_module_segment_word(segments) != name_hash_lo[core_id] ||
            dependency_module_segment_word(segments + 1u) != name_hash_hi[core_id] ||
            dependency_module_segment_word(segments + 4u) != name_hash_lo[range_module_id] ||
            dependency_module_segment_word(segments + 5u) != name_hash_hi[range_module_id])
            return 0u;
        uint name_lo = dependency_declaration_word(base + 1u);
        uint name_hi = dependency_declaration_word(base + 2u);
        uint range_id = language_name_id[65u];
        uint inclusive_id = language_name_id[66u];
        if (name_lo == name_hash_lo[range_id] && name_hi == name_hash_hi[range_id]) kind = 1u;
        else if (name_lo == name_hash_lo[inclusive_id] && name_hi == name_hash_hi[inclusive_id]) kind = 2u;
    }
    else
    {
        uint token = type_instance_decl_token[instance];
        if (token >= gParams.n_tokens) return 0u;
        uint declaration = decl_id_by_name_token[token];
        if (declaration >= gParams.n_hir_nodes) return 0u;
        uint module = decl_module_id[declaration];
        if (module >= gParams.n_hir_nodes || module_key_segment_count[module] != 2u) return 0u;
        uint base = module_key_segment_base[module];
        if (base >= gParams.n_tokens || gParams.n_tokens - base < 2u) return 0u;
        if (module_key_segment_name_id[base] != language_name_id[63u] ||
            module_key_segment_name_id[base + 1u] != language_name_id[64u]) return 0u;
        uint name = decl_name_id[declaration];
        if (name == language_name_id[65u]) kind = 1u;
        else if (name == language_name_id[66u]) kind = 2u;
    }
    uint tag; uint argument;
    if (kind == 0u || type_instance_arg_count[instance] != 1u ||
        !ScopedCheckedTypeGraph.argument(instance, 0u, tag, argument) ||
        tag != 1u || !scalar_is_integer(argument)) return 0u;
    scalar = argument;
    return kind;
}

static const uint INVALID = 0xffffffffu;
static const uint PLAN_NONE = 0u;
static const uint PLAN_FOR = 1u;
static const uint PLAN_LET = 2u;
static const uint PLAN_TRY = 3u;
// ReturnMismatch details of a `?` (typecheck.rs try_diagnostic).
static const uint TRY_NOT_RESULT = 0x3f01u;
static const uint TRY_RETURN_MISMATCH = 0x3f02u;

// One declaration a lane may publish: its token, the planned type `value`,
// the published type `previous`, and what the IDs must still decide.
struct BindingPlan
{
    uint mode;
    uint node;
    uint token;
    uint2 value;
    uint2 previous;
    uint iterable_kind;
    // PLAN_FOR: the value is an iterable's element and must be well formed.
    bool element;
    // PLAN_LET: the value is a call result row and must be closed.
    bool call_result;
    uint initializer;
    uint initializer_kind;
    // PLAN_TRY: the operand's and the function result's error types (scalar
    // never for Option, which has none).
    uint2 error;
    uint2 expected_error;
}

BindingPlan no_plan()
{
    BindingPlan plan;
    plan.mode = PLAN_NONE;
    plan.node = INVALID;
    plan.token = INVALID;
    plan.value = uint2(0u, INVALID);
    plan.previous = uint2(0u, INVALID);
    plan.iterable_kind = 0u;
    plan.element = false;
    plan.call_result = false;
    plan.initializer = INVALID;
    plan.initializer_kind = 0u;
    plan.error = uint2(1u, SCALAR_NEVER);
    plan.expected_error = uint2(1u, SCALAR_NEVER);
    return plan;
}

// Scoped equality of two operands with their canonical IDs.
bool same_type(uint2 left, uint left_id, uint2 right, uint right_id)
{
    return checked_types_equal_ids(CheckedSlots(), left.x, left.y, left_id,
        right.x, right.y, right_id, true);
}

void publish_for_binding(BindingPlan plan, uint value_id, uint previous_id)
{
    uint node = plan.node;
    uint token = plan.token;
    uint tag = plan.value.x;
    uint payload = plan.value.y;
    uint iterable_kind = plan.iterable_kind;
    // An element must be a well-formed type: equal to itself.
    if (plan.element && !same_type(plan.value, value_id, plan.value, value_id))
    { tag = 0u; payload = INVALID; iterable_kind = 0u; }
    bool same = decl_type_ref_tag[token] == tag && decl_type_ref_payload[token] == payload;
    if (!same && tag != 0u)
        same = same_type(plan.previous, previous_id, uint2(tag, payload), value_id);
    bool changed = !same || semantic_iterable_kind_by_hir[node] != iterable_kind;
    decl_type_ref_tag[token] = tag;
    decl_type_ref_payload[token] = payload;
    visible_type[token] = tag == 1u ? payload : 0u;
    semantic_iterable_kind_by_hir[node] = iterable_kind;
    if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}

BindingPlan plan_for_binding(uint node, HirPayload statement, uint count)
{
    BindingPlan plan = no_plan();
    if (statement.b >= gParams.n_tokens) return plan;
    uint source = for_value_root(statement.c, count);
    uint tag = 0u; uint payload = INVALID; uint iterable_kind = 0u;
    if (source < count)
    {
        HirCore source_core = compact_hir_core[source];
        HirPayload range = compact_hir_payload[source];
        bool direct = (source_core.kind == 14u || source_core.kind == 16u) &&
            range.a >= 30u && range.a <= 35u;
        if (direct)
        {
            uint left = for_value_root(range.b, count);
            uint right = for_value_root(range.c, count);
            bool has_left = range.a == 30u || range.a == 31u || range.a == 34u;
            bool has_right = range.a == 30u || range.a == 32u || range.a == 34u || range.a == 35u;
            bool left_ok = !has_left || (left < count && call_inference_result_tag[left] == 1u &&
                scalar_is_integer(call_inference_result_payload[left]));
            bool right_ok = !has_right || (right < count && call_inference_result_tag[right] == 1u &&
                scalar_is_integer(call_inference_result_payload[right]));
            if (left_ok && right_ok)
            {
                uint left_type = has_left ? call_inference_result_payload[left] : 0u;
                uint right_type = has_right ? call_inference_result_payload[right] : 0u;
                if (!has_left || !has_right || left_type == right_type)
                {
                    tag = 1u;
                    payload = has_left ? left_type : has_right ? right_type : 3u;
                }
            }
        }
        else if (call_inference_result_tag[source] == 3u)
        {
            uint instance = call_inference_result_payload[source];
            if (instance < checked_type_capacity())
            {
                uint kind = type_instance_kind[instance];
                if (kind == 2u || kind == 3u)
                {
                    tag = type_instance_elem_ref_tag[instance];
                    payload = type_instance_elem_ref_payload[instance];
                    iterable_kind = kind == 2u ? 3u : 0u;
                    plan.element = true;
                }
                else if (kind == 1u)
                {
                    bool resident; uint scalar;
                    iterable_kind = named_for_range_kind(instance, resident, scalar);
                    if (!resident) return plan;
                    if (iterable_kind != 0u) { tag = 1u; payload = scalar; }
                }
            }
        }
    }
    plan.mode = PLAN_FOR;
    plan.node = node;
    plan.token = statement.b;
    plan.value = uint2(tag, payload);
    plan.previous = uint2(decl_type_ref_tag[statement.b], decl_type_ref_payload[statement.b]);
    plan.iterable_kind = iterable_kind;
    return plan;
}

// Whether checked row `instance` is `core::result::Result` (1) or
// `core::option::Option` (2), else 0. `resident` is false when the
// declaration is on another dependency page, which decides it instead.
uint try_enum_form(uint instance, out bool resident)
{
    resident = true;
    if (instance >= checked_type_capacity() || type_instance_kind[instance] != 1u)
        return 0u;
    uint module_name = INVALID;
    uint name = INVALID;
    uint library_id = external_type_library_id[instance];
    uint unit_id = external_type_unit_id[instance];
    uint local_id = external_type_local_index[instance];
    if (library_id != INVALID && unit_id != INVALID && local_id != INVALID)
    {
        uint declaration = dependency_find_declaration(library_id, unit_id, local_id);
        if (declaration == INVALID) { resident = false; return 0u; }
        uint base = declaration * 14u;
        uint module = dependency_declaration_word(base);
        if (module >= dependency_module_count()) return 0u;
        uint segment_base = dependency_module_word(module * 2u);
        uint capacity = dependency_count(2u);
        if (dependency_module_word(module * 2u + 1u) != 2u || segment_base >= capacity ||
            capacity - segment_base < 2u)
            return 0u;
        uint segments = segment_base * 4u;
        uint core_id = language_name_id[63u];
        if (dependency_module_segment_word(segments) != name_hash_lo[core_id] ||
            dependency_module_segment_word(segments + 1u) != name_hash_hi[core_id])
            return 0u;
        for (uint symbol = 75u; symbol <= 78u; symbol++)
        {
            uint id = language_name_id[symbol];
            if (dependency_module_segment_word(segments + 4u) == name_hash_lo[id] &&
                dependency_module_segment_word(segments + 5u) == name_hash_hi[id])
                module_name = symbol;
            if (dependency_declaration_word(base + 1u) == name_hash_lo[id] &&
                dependency_declaration_word(base + 2u) == name_hash_hi[id])
                name = symbol;
        }
    }
    else
    {
        uint token = type_instance_decl_token[instance];
        if (token >= gParams.n_tokens) return 0u;
        uint declaration = decl_id_by_name_token[token];
        if (declaration >= gParams.n_hir_nodes) return 0u;
        uint module = decl_module_id[declaration];
        if (module >= gParams.n_hir_nodes || module_key_segment_count[module] != 2u) return 0u;
        uint base = module_key_segment_base[module];
        if (base >= gParams.n_tokens || gParams.n_tokens - base < 2u ||
            module_key_segment_name_id[base] != language_name_id[63u]) return 0u;
        for (uint symbol = 75u; symbol <= 78u; symbol++)
        {
            uint id = language_name_id[symbol];
            if (module_key_segment_name_id[base + 1u] == id) module_name = symbol;
            if (decl_name_id[declaration] == id) name = symbol;
        }
    }
    // Symbols 75-78 are result, Result, option, Option.
    if (module_name == 75u && name == 76u && type_instance_arg_count[instance] == 2u) return 1u;
    if (module_name == 77u && name == 78u && type_instance_arg_count[instance] == 1u) return 2u;
    return 0u;
}

bool same_nominal_declaration(uint left, uint right)
{
    return type_instance_kind[right] == 1u &&
        type_instance_decl_token[left] == type_instance_decl_token[right] &&
        external_type_library_id[left] == external_type_library_id[right] &&
        external_type_unit_id[left] == external_type_unit_id[right] &&
        external_type_local_index[left] == external_type_local_index[right];
}

void record_try_error(uint token, uint detail)
{
    // Inference rounds publish provisional facts; the final run diagnoses.
    if (call_inference_state[0u] == 0u)
        record_min_token_error(status, token, 4u, detail);
}

BindingPlan plan_try(uint node, uint count)
{
    BindingPlan plan = no_plan();
    HirCore core = compact_hir_core[node];
    uint operand = compact_hir_payload[node].b;
    uint token = core.token_end - 1u;
    if (operand >= count || core.token_end == 0u || token >= gParams.n_tokens) return plan;
    uint tag = call_inference_result_tag[operand];
    uint payload = call_inference_result_payload[operand];
    if (tag == 0u && compact_hir_core[operand].kind == 19u)
    {
        payload = call_result_instance[operand];
        tag = 3u;
    }
    if (tag == 0u || payload == INVALID) return plan;
    bool resident = true;
    uint form = tag == 3u ? try_enum_form(payload, resident) : 0u;
    if (!resident) return plan;
    if (form == 0u) { record_try_error(token, TRY_NOT_RESULT); return plan; }
    uint function = compact_hir_nearest_fn[node];
    uint function_token = function < count ? compact_hir_payload[function].b : INVALID;
    if (function_token >= gParams.n_tokens) return plan;
    uint expected = fn_return_ref_payload[function_token];
    if (fn_return_ref_tag[function_token] != 3u || expected >= checked_type_capacity() ||
        !same_nominal_declaration(payload, expected))
    { record_try_error(token, TRY_RETURN_MISMATCH); return plan; }
    uint value_tag; uint value;
    if (!ScopedCheckedTypeGraph.argument(payload, 0u, value_tag, value)) return plan;
    if (form == 1u)
    {
        uint error_tag; uint error; uint expected_tag; uint expected_error;
        if (!ScopedCheckedTypeGraph.argument(payload, 1u, error_tag, error) ||
            !ScopedCheckedTypeGraph.argument(expected, 1u, expected_tag, expected_error))
            return plan;
        plan.error = uint2(error_tag, error);
        plan.expected_error = uint2(expected_tag, expected_error);
    }
    plan.mode = PLAN_TRY;
    plan.node = node;
    plan.token = token;
    plan.value = uint2(value_tag, value);
    plan.previous = uint2(decl_type_ref_tag[token], decl_type_ref_payload[token]);
    plan.initializer = operand;
    return plan;
}

// The payload type at the `?` token, once the operand and the error types
// are complete and the error types are identical.
void publish_try(BindingPlan plan, uint4 ids)
{
    uint token = plan.token;
    bool complete = (plan.value.x != 3u || (ct_is_resolved(ids.x) && ct_closed(ids.x))) &&
        (plan.error.x != 3u || (ct_is_resolved(ids.z) && ct_closed(ids.z))) &&
        (plan.expected_error.x != 3u || (ct_is_resolved(ids.w) && ct_closed(ids.w)));
    if (!complete) { clear_unavailable_inferred_declaration(token); return; }
    if (!same_type(plan.error, ids.z, plan.expected_error, ids.w))
    {
        record_try_error(token, TRY_RETURN_MISMATCH);
        clear_unavailable_inferred_declaration(token);
        return;
    }
    if (decl_type_ref_tag[token] != plan.value.x || decl_type_ref_payload[token] != plan.value.y)
    {
        bool changed = !same_type(plan.previous, ids.y, plan.value, ids.x);
        decl_type_ref_tag[token] = plan.value.x;
        decl_type_ref_payload[token] = plan.value.y;
        if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
    }
    visible_type[token] = plan.value.x == 1u ? plan.value.y : 0u;
}

BindingPlan plan_let_binding(uint node, uint kind, HirPayload statement, uint count)
{
    BindingPlan plan = no_plan();
    if ((kind != 7u && kind != 8u) || statement.a != 1u ||
        statement.b >= gParams.n_tokens || statement.d < count) return plan;
    uint initializer = statement.c;
    for (uint depth = 0u; depth < 64u && initializer < count; depth++)
    {
        uint kind = compact_hir_core[initializer].kind;
        HirPayload value = compact_hir_payload[initializer];
        if ((kind == 14u || kind == 16u || kind == 17u) && value.a == 1u)
            initializer = value.b;
        else break;
    }
    if (initializer >= count) return plan;
    uint initializer_kind = compact_hir_core[initializer].kind;
    // Only these forms publish into the accepted expression relation used
    // below. Other initializer producers retain ownership of their facts:
    // kinds 14, 16, 17, 19-24, 28, 33, 34 and 36, as bits of (kind - 14).
    uint owned_kind = initializer_kind - 14u;
    if (owned_kind > 22u || ((0x5847edu >> owned_kind) & 1u) == 0u) return plan;
    if (owned_kind == 0u || owned_kind - 2u <= 1u)
    {
        uint operation = compact_hir_payload[initializer].a;
        // Range and other non-scalar forms have separate type producers.
        // Scalar operators are forms 4-25; a cast (36) has its target type.
        if (operation - 4u > 21u && operation != 36u) return plan;
    }
    uint tag = call_inference_result_tag[initializer];
    uint payload = call_inference_result_payload[initializer];
    if (tag == 0u && initializer_kind == 19u)
    {
        payload = call_result_instance[initializer];
        tag = 3u;
        plan.call_result = true;
    }
    plan.mode = PLAN_LET;
    plan.node = node;
    plan.token = statement.b;
    plan.value = uint2(tag, payload);
    plan.previous = uint2(decl_type_ref_tag[statement.b], decl_type_ref_payload[statement.b]);
    plan.initializer = initializer;
    plan.initializer_kind = initializer_kind;
    return plan;
}

void publish_let_binding(BindingPlan plan, uint value_id, uint previous_id, uint count)
{
    uint token = plan.token;
    uint tag = plan.value.x;
    uint payload = plan.value.y;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    // A call result row must be closed: no parameter leaf, concrete counts.
    if (plan.call_result && !(ct_is_resolved(value_id) && ct_closed(value_id)))
    { clear_unavailable_inferred_declaration(token); return; }
    if (tag != 1u && tag != 2u && tag != 3u)
    { clear_unavailable_inferred_declaration(token); return; }
    if ((tag == 1u && (payload == 0u || payload == 0xffffffffu)) ||
        (tag == 2u && (payload >= gParams.n_tokens || type_generic_param_slot_by_token[payload] == 0xffffffffu)) ||
        (tag == 3u && (payload >= capacity || type_instance_kind[payload] == 0u)))
    { clear_unavailable_inferred_declaration(token); return; }
    if (decl_type_ref_tag[token] != tag || decl_type_ref_payload[token] != payload)
    {
        bool changed = !same_type(plan.previous, previous_id, plan.value, value_id);
        decl_type_ref_tag[token] = tag;
        decl_type_ref_payload[token] = payload;
        if (changed)
        {
            uint ignored;
            InterlockedAdd(call_inference_state[1u], 1u, ignored);
        }
    }
    // A newly structural result must not retain a previous scalar cache.
    visible_type[token] = tag == 1u ? payload : 0u;
    if (plan.initializer_kind != 19u) return;
    uint callee = compact_hir_payload[plan.initializer].a;
    if (callee >= count) return;
    uint callee_token = compact_hir_core[callee].kind == 21u
        ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (callee_token >= gParams.n_tokens) callee_token = compact_hir_core[callee].token_start;
    if (callee_token < gParams.n_tokens && call_return_type[callee_token] != 0u &&
        call_return_type[callee_token] != 0xffffffffu)
        visible_type[token] = call_return_type[callee_token];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count) return;
    uint kind = compact_hir_core[node].kind;
    HirPayload statement = compact_hir_payload[node];
    BindingPlan plan;
    if (kind == 30u || (kind == 7u && statement.a == 7u))
        plan = plan_for_binding(node, statement, count);
    else if (kind == 36u)
        plan = plan_try(node, count);
    else
        plan = plan_let_binding(node, kind, statement, count);
    if (plan.mode == PLAN_NONE) return;
    uint spare = CT_NONE;
    uint4 ids = uint4(CT_UNKNOWN, CT_UNKNOWN, CT_UNKNOWN, CT_UNKNOWN);
    uint operands = plan.mode == PLAN_TRY ? 4u : 2u;
    [loop]
    for (uint index = 0u; index < operands; index++)
    {
        uint2 operand = index == 0u ? plan.value : index == 1u ? plan.previous
            : index == 2u ? plan.error : plan.expected_error;
        uint id = ct_intern_checked<CtCheckedRows>(operand.x, operand.y, spare);
        if (index == 0u) ids.x = id;
        else if (index == 1u) ids.y = id;
        else if (index == 2u) ids.z = id;
        else ids.w = id;
    }
    if (plan.mode == PLAN_FOR) publish_for_binding(plan, ids.x, ids.y);
    else if (plan.mode == PLAN_TRY) publish_try(plan, ids);
    else publish_let_binding(plan, ids.x, ids.y, count);
}
