// Carry an expression's accepted complete type into an unannotated declaration.
// Initializers and result rows are immutable here; each statement owns its
// declaration, so name/index/member readers need no source-text inference.
import hir_records;
import hir_expr_semantics;
import primitive_types;
import dependency_interface;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;

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
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;

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

void publish_for_binding(uint node, uint token, uint tag, uint payload, uint iterable_kind)
{
    bool same = decl_type_ref_tag[token] == tag && decl_type_ref_payload[token] == payload;
    if (!same && tag != 0u)
        same = scoped_type_refs_equal<ScopedCheckedTypeGraph>(
            decl_type_ref_tag[token], decl_type_ref_payload[token], 0xffffffffu,
            tag, payload, 0xffffffffu, checked_type_capacity(), gParams.n_tokens);
    bool changed = !same || semantic_iterable_kind_by_hir[node] != iterable_kind;
    decl_type_ref_tag[token] = tag;
    decl_type_ref_payload[token] = payload;
    visible_type[token] = tag == 1u ? payload : 0u;
    semantic_iterable_kind_by_hir[node] = iterable_kind;
    if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}

void infer_for_binding(uint node, HirPayload statement, uint count)
{
    static const uint INVALID = 0xffffffffu;
    if (statement.b >= gParams.n_tokens) return;
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
                    if (!scoped_type_refs_equal<ScopedCheckedTypeGraph>(tag, payload, INVALID,
                        tag, payload, INVALID, checked_type_capacity(), gParams.n_tokens))
                    { tag = 0u; payload = INVALID; iterable_kind = 0u; }
                }
                else if (kind == 1u)
                {
                    bool resident; uint scalar;
                    iterable_kind = named_for_range_kind(instance, resident, scalar);
                    if (!resident) return;
                    if (iterable_kind != 0u) { tag = 1u; payload = scalar; }
                }
            }
        }
    }
    publish_for_binding(node, statement.b, tag, payload, iterable_kind);
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
    if (kind == 30u || (kind == 7u && statement.a == 7u))
    {
        infer_for_binding(node, statement, count);
        return;
    }
    if ((kind != 7u && kind != 8u) || statement.a != 1u ||
        statement.b >= gParams.n_tokens || statement.d < count) return;
    uint initializer = statement.c;
    for (uint depth = 0u; depth < 64u && initializer < count; depth++)
    {
        uint kind = compact_hir_core[initializer].kind;
        HirPayload value = compact_hir_payload[initializer];
        if ((kind == 14u || kind == 16u || kind == 17u) && value.a == 1u)
            initializer = value.b;
        else break;
    }
    if (initializer >= count) return;
    uint initializer_kind = compact_hir_core[initializer].kind;
    // Only these forms publish into the accepted expression relation used
    // below. Other initializer producers retain ownership of their facts:
    // kinds 14, 16, 17, 19-24, 28, 33 and 34, as bits of (kind - 14).
    uint owned_kind = initializer_kind - 14u;
    if (owned_kind > 20u || ((0x1847edu >> owned_kind) & 1u) == 0u) return;
    if (owned_kind == 0u || owned_kind - 2u <= 1u)
    {
        uint operation = compact_hir_payload[initializer].a;
        // Range and other non-scalar forms have separate type producers.
        // Scalar operators are forms 4-25; a cast (36) has its target type.
        if (operation - 4u > 21u && operation != 36u) return;
    }
    uint tag = call_inference_result_tag[initializer];
    uint payload = call_inference_result_payload[initializer];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (tag == 0u && initializer_kind == 19u)
    {
        payload = call_result_instance[initializer];
        if (!checked_instance_is_closed(payload))
        { clear_unavailable_inferred_declaration(statement.b); return; }
        tag = 3u;
    }
    if (tag != 1u && tag != 2u && tag != 3u)
    { clear_unavailable_inferred_declaration(statement.b); return; }
    if ((tag == 1u && (payload == 0u || payload == 0xffffffffu)) ||
        (tag == 2u && (payload >= gParams.n_tokens || type_generic_param_slot_by_token[payload] == 0xffffffffu)) ||
        (tag == 3u && (payload >= capacity || type_instance_kind[payload] == 0u)))
    { clear_unavailable_inferred_declaration(statement.b); return; }
    if (decl_type_ref_tag[statement.b] != tag || decl_type_ref_payload[statement.b] != payload)
    {
        uint previous_tag = decl_type_ref_tag[statement.b];
        uint previous_payload = decl_type_ref_payload[statement.b];
        bool changed = !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
            previous_tag, previous_payload, 0xffffffffu, tag, payload, 0xffffffffu,
            checked_type_capacity(), gParams.n_tokens);
        decl_type_ref_tag[statement.b] = tag;
        decl_type_ref_payload[statement.b] = payload;
        if (changed)
        {
            uint ignored;
            InterlockedAdd(call_inference_state[1u], 1u, ignored);
        }
    }
    // A newly structural result must not retain a previous scalar cache.
    visible_type[statement.b] = tag == 1u ? payload : 0u;
    if (initializer_kind != 19u) return;
    uint callee = compact_hir_payload[initializer].a;
    if (callee >= count) return;
    uint token = compact_hir_core[callee].kind == 21u
        ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token < gParams.n_tokens && call_return_type[token] != 0u && call_return_type[token] != 0xffffffffu)
        visible_type[statement.b] = call_return_type[token];
}
