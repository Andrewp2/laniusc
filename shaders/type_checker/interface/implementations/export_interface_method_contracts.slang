// Emit one lexical implementation's complete header and callable contracts.
// Every method/header position is deterministic within its disjoint segment.
import hir_records;
import atomics;
import callable_identity;
import semantic_interface_layout;
import type_checker.constant_parameter_slots;
import type_checker.interface.method_parameters;
import constant_value;
import type_checker.constant_atoms;
import type_checker.interface.scalar_leaves;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_validation_required_symbol;
StructuredBuffer<uint> interface_implementation_flag;
StructuredBuffer<uint> interface_implementation_prefix;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_implementation_first_method_row;
StructuredBuffer<uint> interface_implementation_member_count;
StructuredBuffer<uint> interface_implementation_member_prefix;
StructuredBuffer<uint> interface_implementation_method_count;
StructuredBuffer<uint> interface_implementation_method_prefix;
StructuredBuffer<uint> interface_implementation_method_total;
StructuredBuffer<uint> interface_declaration_member_total;
StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_member_words;
RWStructuredBuffer<uint> interface_member_name_id;
RWStructuredBuffer<uint> interface_member_written;
RWStructuredBuffer<uint> interface_member_index_by_generic_row;
RWStructuredBuffer<uint> interface_implementation_method_binding_words;
RWStructuredBuffer<uint> interface_implementation_method_binding_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 131072u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}
bool emit_member(uint destination, uint owner, uint kind, uint ordinal,
    uint name, uint type_index, uint value_lo, uint symbol, uint receiver,
    uint source_ordinal, uint detail)
{
    if (destination >= interface_member_total[0u] || name == INVALID ||
        (kind != 2u && type_index == INVALID) ||
        atomic_u32_compare_exchange(interface_member_written, destination, 0u, 1u) != 0u)
    { fail(detail, 47u); return false; }
    uint base = destination * SEMANTIC_INTERFACE_MEMBER_WORDS;
    interface_member_words[base] = owner;
    interface_member_words[base + 1u] = kind;
    interface_member_words[base + 2u] = ordinal;
    for (uint word = 3u; word <= 6u; word++) interface_member_words[base + word] = 0u;
    interface_member_words[base + 7u] = type_index;
    interface_member_words[base + 8u] = value_lo;
    interface_member_words[base + 9u] = symbol;
    interface_member_words[base + 10u] = receiver;
    interface_member_words[base + 11u] = source_ordinal;
    interface_member_name_id[destination] = name;
    return true;
}
bool emit_header(uint hir, uint scope, uint owner, uint first, uint member_count,
    inout uint ordinal, out uint type_count, out uint constant_count, uint detail)
{
    type_count = 0u; constant_count = 0u;
    HirRange range = compact_generic_param_ranges[hir];
    uint total = min(compact_generic_param_count[0u], gParams.hir_capacity);
    if (range.count > 64u || (range.count != 0u &&
        (range.start > total || range.count > total - range.start)) ||
        ordinal > member_count || range.count > member_count - ordinal)
    { fail(detail, 50u); return false; }
    for (uint n = 0u; n < range.count; n++)
    {
        uint row = range.start + n;
        HirGenericParam parameter = compact_generic_params[row];
        uint token = parameter.name_token;
        if (parameter.owner != hir || token >= gParams.token_capacity ||
            (parameter.kind != 1u && parameter.kind != 2u))
        { fail(detail, 50u); return false; }
        uint slot = parameter.kind == 1u ? type_generic_param_slot_by_token[token] : type_const_param_slot_by_token[token];
        if (slot >= 32u) { fail(detail, 50u); return false; }
        uint declared_type = INVALID;
        if (parameter.kind == 2u)
        {
            uint scalar = checked_constant_parameter_scalar(token);
            if (!constant_scalar_is_supported(scalar)) { fail(detail, 50u); return false; }
            declared_type = interface_scalar_leaf_index(interface_type_count[0u], scalar);
        }
        if (parameter.kind == 1u) type_count++; else constant_count++;
        uint destination = first + ordinal;
        if (!emit_member(destination, owner, parameter.kind == 1u ? 2u : 3u, ordinal++,
            name_id_by_token[token], declared_type, slot, scope, INVALID, n, detail)) return false;
        interface_member_index_by_generic_row[row] = destination;
    }
    return true;
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    uint rows; uint stride;
    interface_implementation_flag.GetDimensions(rows, stride);
    if (row >= min(active, rows) || interface_implementation_flag[row] != 1u) return;
    uint implementation = interface_implementation_prefix[row];
    bool inherent = compact_hir_semantic_facts[row].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT;
    uint subject_hir = compact_hir_semantic_facts[row].method_impl_receiver_type;
    if (implementation >= interface_implementation_total[0u] || predicate_status[row] != 0u)
    { fail(row, 40u); return; }
    uint member_count = interface_implementation_member_count[implementation];
    uint member_offset = interface_implementation_member_prefix[implementation];
    uint declaration_members = interface_declaration_member_total[0u];
    uint members = interface_member_total[0u];
    uint member_rows;
    interface_member_written.GetDimensions(member_rows, stride);
    if (members > member_rows || declaration_members > members ||
        member_offset > members - declaration_members || member_count > members - declaration_members - member_offset)
    { fail(row, 41u); return; }
    uint first_member = declaration_members + member_offset;
    uint binding_count = interface_implementation_method_count[implementation];
    uint first_binding = interface_implementation_method_prefix[implementation];
    uint bindings = interface_implementation_method_total[0u];
    uint binding_rows;
    interface_implementation_method_binding_written.GetDimensions(binding_rows, stride);
    if (bindings > binding_rows || first_binding > bindings || binding_count > bindings - first_binding)
    { fail(row, 42u); return; }
    uint owner = SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER | implementation;
    uint ordinal = 0u; uint impl_types = 0u; uint impl_constants = 0u;
    if (!emit_header(row, 0xc0000000u | row, owner, first_member, member_count,
        ordinal, impl_types, impl_constants, row)) return;
    uint methods = min(compact_method_count[0u], active);
    uint first_method = interface_implementation_first_method_row[row];
    uint emitted_bindings = 0u;
    uint parameters = min(compact_param_count[0u], active);
    for (uint method_row = first_method; method_row < methods; method_row++)
    {
        HirMethodCore method = compact_method_cores[method_row];
        if (method.impl_node != row) break;
        HirMethodSignature signature = compact_method_signatures[method_row];
        if (inherent && !interface_public_inherent_method(signature)) continue;
        if (method.node >= active || method.owner != row ||
            (!inherent && (predicate_method_validation_status[method.node] != 0u ||
            ((signature.metadata >> 16u) & 3u) != 0u || compact_generic_param_ranges[method.node].count != 0u)))
        { fail(row, 44u); return; }
        uint required_symbol = inherent ? INVALID : predicate_method_validation_required_symbol[method.node];
        uint visibility = signature.metadata & 0xffffu;
        uint mode = signature.receiver_mode;
        bool implicit_self = mode == 1u || mode == 2u;
        HirRange range = compact_param_ranges[method.node];
        if ((!inherent && (required_symbol == INVALID || (required_symbol & 0xc0000000u) != 0x80000000u)) ||
            mode > 3u || visibility > 1u || range.count > 65535u ||
            (implicit_self && range.count == 0u) ||
            (range.count != 0u && (range.start > parameters || range.count > parameters - range.start)))
        { fail(row, 45u); return; }
        uint symbol = interface_method_symbol(method.node);
        uint own_types; uint own_constants;
        if (!emit_header(method.node, symbol, owner, first_member, member_count,
            ordinal, own_types, own_constants, row)) return;
        uint type_count = impl_types + own_types;
        uint constant_count = impl_constants + own_constants;
        uint explicit_count = range.count - uint(implicit_self);
        if (type_count > 32u || constant_count > 32u || ordinal >= member_count || explicit_count > member_count - ordinal - 1u)
        { fail(row, 46u); return; }
        uint receiver_hir = signature.impl_receiver_type;
        uint return_hir = compact_fn_return_type[method.node];
        if (receiver_hir >= active || receiver_hir != subject_hir || (return_hir != INVALID && return_hir >= active))
        { fail(row, 46u); return; }
        uint receiver = interface_type_index_by_hir[receiver_hir];
        uint result = return_hir == INVALID ? interface_type_count[0u] : interface_type_index_by_hir[return_hir];
        uint name = method.name_token < gParams.token_capacity ? name_id_by_token[method.name_token] : INVALID;
        uint requirements = explicit_count | (type_count << 16u) | (constant_count << 22u) | (mode << 28u) | (visibility << 30u);
        uint method_member = first_member + ordinal;
        if (receiver == INVALID || !emit_member(method_member, owner, 8u, ordinal++,
            name, result, requirements, symbol, receiver, INVALID, row)) return;
        for (uint n = 0u; n < range.count; n++)
        {
            HirParam parameter = compact_params[range.start + n];
            if (parameter.owner != method.node || parameter.ordinal != n)
            { fail(row, 48u); return; }
            if (implicit_self && n == 0u) continue;
            if (parameter.type_node >= active || parameter.name_token >= gParams.token_capacity)
            { fail(row, 48u); return; }
            uint destination = first_member + ordinal;
            if (!emit_member(destination, owner, 1u, ordinal++,
                name_id_by_token[parameter.name_token], interface_type_index_by_hir[parameter.type_node],
                n, symbol, INVALID, INVALID, row)) return;
        }
        if (inherent) continue;
        if (emitted_bindings >= binding_count) { fail(row, 49u); return; }
        uint binding = first_binding + emitted_bindings++;
        if (atomic_u32_compare_exchange(interface_implementation_method_binding_written, binding, 0u, 1u) != 0u)
        { fail(row, 49u); return; }
        uint base = binding * SEMANTIC_INTERFACE_IMPLEMENTATION_METHOD_BINDING_WORDS;
        interface_implementation_method_binding_words[base] = implementation;
        interface_implementation_method_binding_words[base + 1u] = required_symbol;
        interface_implementation_method_binding_words[base + 2u] = method_member;
        interface_implementation_method_binding_words[base + 3u] = gParams.library_id;
        interface_implementation_method_binding_words[base + 4u] = gParams.unit_id;
        interface_implementation_method_binding_words[base + 5u] = local_callable_symbol(
            INVALID, method.node, visibility == 1u, compact_hir_core[method.node].token_start);
    }
    if (ordinal != member_count || emitted_bindings != binding_count) fail(row, 46u);
}
