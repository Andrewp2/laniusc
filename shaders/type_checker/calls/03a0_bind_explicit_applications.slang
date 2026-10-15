import type_checker.constant_parameter_slots;
// Bind only the callable's own ordered header. Method lexical slots already
// include the impl domain; the receiver producer owns those inherited bindings.
import hir_records;
import type_checker.calls.explicit_application_owner;
import type_checker.calls.explicit_binding_metadata;
import type_checker.calls.explicit_constant_operand;
import type_checker.calls.claim_reference;
import type_checker.checked_type_graph;
import type_checker.concrete_type_equality;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;
StructuredBuffer<uint> resolved_value_type_qualifier_token;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> call_explicit_application_owner_by_token;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

// Constant operands read checked type references through this kernel's binding.
struct KernelTypeRefs : IExplicitOperandTypeRefs
{
    uint type_ref_tag(uint token) { return type_expr_ref_tag[token]; }
    uint type_ref_payload(uint token) { return type_expr_ref_payload[token]; }
}
RWStructuredBuffer<uint4> call_explicit_environment;
RWStructuredBuffer<uint> call_explicit_binding_tag;
RWStructuredBuffer<uint> call_explicit_binding_payload;
RWStructuredBuffer<uint> call_explicit_binding_count;

// A bounded compact arena keeps application storage proportional to source
// size. Each applying token reserves once, including across inference rounds.
// An application's bindings are its type slots in ascending order, then its
// constant slots in ascending order. A binding's row is the base plus its rank
// among the set slots, so each one is written straight to its row.
bool reserve_bindings(uint token, uint type_mask, uint constant_mask, out uint base)
{
    base = 0u;
    uint count = countbits(type_mask) + countbits(constant_mask);
    uint4 descriptor = call_explicit_environment[token];
    uint capacity; uint stride;
    call_explicit_binding_tag.GetDimensions(capacity, stride);
    if (descriptor.x == 0u)
    {
        uint start;
        InterlockedAdd(call_explicit_binding_count[0u], max(count, 1u), start);
        if (start >= capacity || count > capacity - start)
        { call_explicit_application_status[token] = 4u; return false; }
        descriptor = uint4(start + 1u, count, 0u, 0u);
    }
    if (descriptor.y < count)
    { call_explicit_application_status[token] = 4u; return false; }
    base = descriptor.x - 1u;
    descriptor.z = type_mask; descriptor.w = constant_mask;
    call_explicit_environment[token] = descriptor;
    return true;
}

void write_type_binding(uint row, uint2 reference)
{
    call_explicit_binding_tag[row] = reference.x;
    call_explicit_binding_payload[row] = reference.y;
}

// Keep constant parameter identities outside the type-reference domain when
// body replay specializes accepted type columns.
void write_constant_binding(uint row, uint2 reference)
{
    call_explicit_binding_tag[row] = reference.x | EXPLICIT_CONSTANT_SLOT;
    call_explicit_binding_payload[row] = reference.y;
}

// One written argument's slot and reference. False when the argument cannot
// bind; `status` is then the application status to publish, or 0 to leave it.
bool source_binding(uint row, uint hir_count, out bool constant, out uint slot,
    out uint2 reference, out uint status)
{
    uint encoded = call_explicit_arg_slot[row];
    constant = (encoded & EXPLICIT_CONSTANT_SLOT) != 0u;
    slot = encoded & ~EXPLICIT_CONSTANT_SLOT;
    reference = uint2(0u, 0u);
    status = 4u;
    uint operand = compact_type_args[row].value;
    if (slot >= 32u || operand >= hir_count) return false;
    status = 0u;
    if (constant)
    {
        reference = uint2(call_explicit_arg_constant_kind[operand],
            call_explicit_arg_constant_payload[operand]);
        return reference.x >= 1u && reference.x <= 3u && reference.y != 0xffffffffu;
    }
    if (compact_hir_core[operand].kind != 5u) { status = 3u; return false; }
    uint anchor = compact_hir_core[operand].token_start;
    if (anchor >= gParams.n_tokens) return false;
    reference = uint2(type_expr_ref_tag[anchor], type_expr_ref_payload[anchor]);
    return checked_claim_reference(reference.x, reference.y);
}

void publish_source_bindings(uint token, HirRange arguments, uint hir_count)
{
    if (call_explicit_application_status[token] != 1u) return;
    uint type_mask = 0u; uint constant_mask = 0u;
    for (uint i = 0u; i < arguments.count; i++)
    {
        bool constant; uint slot; uint2 reference; uint status;
        bool bound = source_binding(arguments.start + i, hir_count, constant, slot,
            reference, status);
        // A slot out of range or repeated fails before the argument's reference.
        if (!bound && status == 4u) { call_explicit_application_status[token] = 4u; return; }
        if (((constant ? constant_mask : type_mask) & (1u << slot)) != 0u)
        { call_explicit_application_status[token] = 4u; return; }
        if (!bound)
        {
            if (status != 0u) call_explicit_application_status[token] = status;
            return;
        }
        if (constant) constant_mask |= 1u << slot; else type_mask |= 1u << slot;
    }
    uint base;
    if (!reserve_bindings(token, type_mask, constant_mask, base)) return;
    uint types = countbits(type_mask);
    for (uint i = 0u; i < arguments.count; i++)
    {
        bool constant; uint slot; uint2 reference; uint status;
        source_binding(arguments.start + i, hir_count, constant, slot, reference, status);
        uint below = (1u << slot) - 1u;
        if (constant)
            write_constant_binding(base + types + countbits(constant_mask & below), reference);
        else write_type_binding(base + countbits(type_mask & below), reference);
    }
}

// One checked parent argument: 1 for a type, 2 for a constant (with the
// constant's kind and payload as its reference), 0 when it cannot bind.
uint parent_binding(uint parent, uint ordinal, out uint2 reference)
{
    if (!ScopedCheckedTypeGraph.argument(parent, ordinal, reference.x, reference.y)) return 0u;
    uint kind; uint payload;
    if (application_constant_argument(reference.x, reference.y, kind, payload))
    { reference = uint2(kind, payload); return 2u; }
    return checked_claim_reference(reference.x, reference.y) ? 1u : 0u;
}

void publish_checked_parent_bindings(uint token, uint parent)
{
    if (parent >= checked_type_capacity() ||
        type_instance_kind[parent] != 1u || type_instance_state[parent] != 1u)
    { call_explicit_application_status[token] = 4u; return; }
    uint count = type_instance_arg_count[parent];
    if (count > 32u)
    { call_explicit_application_status[token] = 4u; return; }
    uint type_count = 0u; uint constant_count = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint2 reference;
        uint binding = parent_binding(parent, ordinal, reference);
        if (binding == 0u) { call_explicit_application_status[token] = 4u; return; }
        if (binding == 2u) constant_count++; else type_count++;
    }
    uint type_mask = type_count == 32u ? 0xffffffffu : (1u << type_count) - 1u;
    uint constant_mask = constant_count == 32u ? 0xffffffffu : (1u << constant_count) - 1u;
    uint base;
    if (!reserve_bindings(token, type_mask, constant_mask, base)) return;
    uint type_row = base; uint constant_row = base + type_count;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint2 reference;
        if (parent_binding(parent, ordinal, reference) == 2u)
            write_constant_binding(constant_row++, reference);
        else write_type_binding(type_row++, reference);
    }
    call_explicit_application_status[token] = 1u;
}

void publish_parent_bindings(uint token, uint owner, bool written_arguments)
{
    uint parent = type_expr_ref_payload[token];
    uint declaration = compact_hir_payload[owner].b;
    // A declaration template supplies no new constraints. A normalized concrete
    // alias has a distinct application even when its source header is empty.
    if (!written_arguments && parent == declaration) return;
    if (type_expr_ref_tag[token] != 3u || parent >= checked_type_capacity() ||
        type_instance_decl_token[parent] != declaration)
    { call_explicit_application_status[token] = 4u; return; }
    publish_checked_parent_bindings(token, parent);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 65535u * 256u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (call >= count || compact_hir_core[call].kind != 19u) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= count) return;
    uint leaf; bool repeated;
    uint token = explicit_callable_application_token(call, count, gParams.n_tokens,
        compact_hir_core, compact_hir_links, compact_hir_payload, path_id_by_owner_hir,
        compact_path_count, compact_paths, compact_path_segments,
        resolved_value_type_qualifier_token, compact_path_type_arg_ranges, leaf, repeated);
    if (token >= gParams.n_tokens) return;
    // Record every checked call alias while preserving the applying segment.
    bool member = compact_hir_core[callee].kind == 21u;
    uint identity = member
        ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (identity >= gParams.n_tokens) identity = compact_hir_core[callee].token_start;
    call_explicit_application_owner_by_token[token] = token;
    if (leaf < gParams.n_tokens) call_explicit_application_owner_by_token[leaf] = token;
    if (identity < gParams.n_tokens) call_explicit_application_owner_by_token[identity] = token;
    // Chained member calls share the receiver span's start. That token cannot
    // identify either application; publishing it would race between call lanes.
    if (!member)
    {
        uint head = compact_hir_core[callee].token_start;
        if (head < gParams.n_tokens) call_explicit_application_owner_by_token[head] = token;
        head = compact_hir_core[call].token_start;
        if (head < gParams.n_tokens) call_explicit_application_owner_by_token[head] = token;
    }
    HirRange arguments = compact_path_type_arg_ranges[token];
    bool written_arguments = arguments.count != 0u;
    if (repeated) { call_explicit_application_status[token] = 2u; return; }
    if (written_arguments && !explicit_application_range(token, arguments)) return;
    if (call_dependency_library_id[token] != 0xffffffffu ||
        (leaf < gParams.n_tokens && call_dependency_library_id[leaf] != 0xffffffffu) ||
        (identity < gParams.n_tokens && call_dependency_library_id[identity] != 0xffffffffu))
    {
        if (token != leaf && call_explicit_application_status[token] == 1u &&
            type_expr_ref_tag[token] == 3u)
            publish_checked_parent_bindings(token, type_expr_ref_payload[token]);
        else if (written_arguments) publish_source_bindings(token, arguments, count);
        return;
    }
    uint function = call_fn_index[token];
    if (function >= gParams.n_tokens && leaf < gParams.n_tokens) function = call_fn_index[leaf];
    if (function >= gParams.n_tokens && identity < gParams.n_tokens) function = call_fn_index[identity];
    if (function >= gParams.n_tokens) return; // Name resolution owns an unknown callable.
    uint owner = fn_hir_by_decl_token[function];
    if (owner >= count)
    {
        if (written_arguments) call_explicit_application_status[token] = 4u;
        return;
    }
    if (token != leaf && compact_hir_core[owner].kind == 26u)
    {
        // The qualifier's own header was checked during type normalization.
        // Its target operands can reorder, omit, or inject source operands.
        publish_parent_bindings(token, owner, written_arguments);
        return;
    }
    if (!written_arguments) return;
    HirRange parameters = compact_generic_param_ranges[owner];
    if (parameters.count != arguments.count)
    { call_explicit_application_status[token] = 2u; return; }
    uint total = compact_generic_param_count[0u];
    if (parameters.start > total || parameters.count > total - parameters.start)
    { call_explicit_application_status[token] = 4u; return; }
    uint seen = 0u; uint constant_seen = 0u;
    for (uint ordinal = 0u; ordinal < parameters.count; ordinal++)
    {
        HirGenericParam parameter = compact_generic_params[parameters.start + ordinal];
        if (parameter.owner != owner || parameter.name_token >= gParams.n_tokens)
        { call_explicit_application_status[token] = 4u; return; }
        if (parameter.kind != 1u && parameter.kind != 2u)
        { call_explicit_application_status[token] = 3u; return; }
        bool constant = parameter.kind == 2u;
        uint slot = constant ? type_const_param_slot_by_token[parameter.name_token]
            : type_generic_param_slot_by_token[parameter.name_token];
        if (slot >= 32u || ((constant ? constant_seen : seen) & (1u << slot)) != 0u)
        { call_explicit_application_status[token] = 4u; return; }
        if (constant)
        {
            if (!bind_explicit_constant_operand(KernelTypeRefs(), arguments.start + ordinal,
                type_const_param_scalar_by_token[parameter.name_token]))
            { call_explicit_application_status[token] = 3u; return; }
            constant_seen |= 1u << slot;
        }
        else seen |= 1u << slot;
        call_explicit_arg_slot[arguments.start + ordinal] = slot | (constant ? EXPLICIT_CONSTANT_SLOT : 0u);
    }
    call_explicit_application_status[token] = 1u;
    publish_source_bindings(token, arguments, count);
}
