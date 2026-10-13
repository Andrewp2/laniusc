// Checked references own exported shape. HIR identifies declaration roots only.
import hir_records;
import atomics;
import type_checker.checked_type_graph;
import type_checker.constant_parameter_slots;
import type_checker.constant_atoms;
import constant_value;
import primitive_types;
import type_checker.type.instances.generic_param_lookup;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
StructuredBuffer<uint> semantic_type_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;
#define LEXICAL_HIR_CAPACITY gParams.hir_capacity
#define LEXICAL_TOKEN_CAPACITY gParams.token_capacity
#include "../../type/instances/lexical_parameter_lookup.slang"
static const uint INVALID = 0xffffffffu;
static const uint EXPORT_DEPTH_LIMIT = 64u;
void checked_export_fail(uint root, uint detail)
{
    atomic_u32_or(interface_status, 0u, 32768u);
    atomic_u32_min(interface_status, 1u, root);
    atomic_u32_min(interface_status, 2u, detail);
}
uint2 checked_export_root(uint node)
{
    return uint2(semantic_type_ref_tag_by_hir[node], semantic_type_ref_payload_by_hir[node]);
}
// Source constant references retain their own row/token domains. Only this
// adapter maps the atom, parameter and projection kinds to checked-graph tags.
bool checked_export_constant_reference(uint kind, uint payload, out uint2 ref)
{
    ref = uint2(0u, INVALID);
    if (kind < 1u || kind > 3u || payload == INVALID) return false;
    ref = uint2(0x80000000u | kind, payload);
    return true;
}
bool checked_export_constant_scalar(uint2 ref, out uint scalar)
{
    scalar = 0u;
    if (ref.x == 0x80000001u)
    {
        uint3 value;
        if (!checked_constant_atom_value(ref.y, value)) return false;
        scalar = value.x;
        return true;
    }
    if (ref.x == 0x80000002u)
    {
        if (ref.y >= gParams.token_capacity || type_const_param_slot_by_token[ref.y] >= 32u) return false;
        scalar = checked_constant_parameter_scalar(ref.y);
        return scalar != 0u;
    }
    uint2 child;
    return ref.x == 0x80000003u && checked_constant_projection(ref.y, scalar, child);
}
bool checked_export_projection(uint row, out uint target, out uint2 child)
{
    uint2 source_child;
    uint child_scalar;
    target = 0u;
    child = uint2(0u, INVALID);
    return checked_constant_projection(row, target, source_child) &&
        scalar_is_integer(target) &&
        checked_export_constant_reference(source_child.x, source_child.y, child) &&
        checked_export_constant_scalar(child, child_scalar) && scalar_is_integer(child_scalar);
}
uint checked_export_kind(uint2 ref, out uint children)
{
    children = 0u;
    if (ref.y == INVALID) return 0u;
    if (ref.x == 1u) return ref.y == 0u ? 0u : 1u;
    if (ref.x == 2u)
        return ref.y < gParams.token_capacity && type_generic_param_slot_by_token[ref.y] < 32u ? 2u : 0u;
    if (ref.x == 0x80000001u)
    {
        uint3 value;
        return checked_constant_atom_value(ref.y, value) && constant_value_is_valid(value) ? 9u : 0u;
    }
    if (ref.x == 0x80000002u)
    {
        uint scalar;
        return checked_export_constant_scalar(ref, scalar) ? 8u : 0u;
    }
    if (ref.x == 0x80000003u)
    {
        uint target;
        uint2 child;
        if (!checked_export_projection(ref.y, target, child)) return 0u;
        children = 1u;
        return 10u;
    }
    if (ref.x != 3u || ref.y >= checked_type_capacity() || type_instance_state[ref.y] != 1u) return 0u;
    uint kind = type_instance_kind[ref.y];
    if (kind < 1u || kind > 4u) return 0u;
    children = kind == 1u ? type_instance_arg_count[ref.y] : kind == 2u ? 2u : 1u;
    if (children > 32u) return 0u;
    if (kind == 2u)
    {
        uint2 length;
        uint scalar;
        if (!checked_export_constant_reference(type_instance_len_kind[ref.y],
            type_instance_len_payload[ref.y], length) ||
            !checked_export_constant_scalar(length, scalar) || !scalar_is_integer(scalar)) return 0u;
    }
    return kind + 2u;
}
bool checked_export_child(uint2 ref, uint ordinal, out uint2 child)
{
    child = uint2(0u, INVALID);
    if (ref.x == 0x80000003u)
    {
        uint target;
        return ordinal == 0u && checked_export_projection(ref.y, target, child);
    }
    if (ref.x != 3u || ref.y >= checked_type_capacity()) return false;
    if (type_instance_kind[ref.y] == 1u)
        return ScopedCheckedTypeGraph.argument(ref.y, ordinal, child.x, child.y);
    if (type_instance_kind[ref.y] == 2u && ordinal == 1u)
    {
        return checked_export_constant_reference(type_instance_len_kind[ref.y],
            type_instance_len_payload[ref.y], child);
    }
    if (ordinal != 0u) return false;
    child = uint2(type_instance_elem_ref_tag[ref.y], type_instance_elem_ref_payload[ref.y]);
    return child.x != 0u && child.y != INVALID;
}
bool checked_export_size(uint node, out uint count)
{
    uint2 refs[EXPORT_DEPTH_LIMIT];
    uint next[EXPORT_DEPTH_LIMIT]; uint children[EXPORT_DEPTH_LIMIT];
    uint depth = 0u; count = 0u;
    refs[0u] = checked_export_root(node); next[0u] = INVALID;
    for (;;)
    {
        if (next[depth] == INVALID)
        {
            if (checked_export_kind(refs[depth], children[depth]) == 0u || count >= gParams.hir_capacity) return false;
            count++; next[depth] = 0u;
        }
        if (next[depth] == children[depth])
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint2 child;
        if (depth + 1u == EXPORT_DEPTH_LIMIT || !checked_export_child(refs[depth], next[depth]++, child)) return false;
        depth++; refs[depth] = child; next[depth] = INVALID;
    }
}
