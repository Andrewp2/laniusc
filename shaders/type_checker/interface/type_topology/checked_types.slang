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
// An export walk keeps two words per level, so its per-thread stack stays
// small: the reference's payload and a packed level word with the tag's code
// (bits 0-2), the next child ordinal (bits 3-8, EXPORT_UNVISITED until the
// node is visited) and the child count (bits 9-14). checked_export_kind
// accepts at most 32 children and only the six tags coded here; any other
// tag codes to 0, which it rejects as before.
static const uint EXPORT_UNVISITED = 63u;
uint export_level(uint2 ref)
{
    uint code = ref.x >= 1u && ref.x <= 3u ? ref.x
        : ref.x >= 0x80000001u && ref.x <= 0x80000003u ? ref.x - 0x80000001u + 4u : 0u;
    return code | (EXPORT_UNVISITED << 3u);
}
uint2 export_level_ref(uint level, uint payload)
{
    uint code = level & 7u;
    return uint2(code <= 3u ? code : 0x80000001u + code - 4u, payload);
}
uint export_level_next(uint level) { return (level >> 3u) & 63u; }
uint export_level_children(uint level) { return level >> 9u; }
// Visited with `children` (at most 32) children; the next ordinal is 0.
uint export_level_visit(uint level, uint children) { return (level & 7u) | (children << 9u); }
uint export_level_advance(uint level) { return level + 8u; }
bool checked_export_size(uint node, out uint count)
{
    uint payload[EXPORT_DEPTH_LIMIT]; uint level[EXPORT_DEPTH_LIMIT];
    uint depth = 0u; count = 0u;
    uint2 top = checked_export_root(node);
    payload[0u] = top.y; level[0u] = export_level(top);
    for (;;)
    {
        uint2 ref = export_level_ref(level[depth], payload[depth]);
        if (export_level_next(level[depth]) == EXPORT_UNVISITED)
        {
            uint children;
            if (checked_export_kind(ref, children) == 0u || count >= gParams.hir_capacity) return false;
            count++; level[depth] = export_level_visit(level[depth], children);
        }
        uint next = export_level_next(level[depth]);
        if (next == export_level_children(level[depth]))
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint2 child;
        level[depth] = export_level_advance(level[depth]);
        if (depth + 1u == EXPORT_DEPTH_LIMIT || !checked_export_child(ref, next, child)) return false;
        depth++; payload[depth] = child.y; level[depth] = export_level(child);
    }
}
