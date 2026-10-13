#include "checked_types.slang"
import semantic_interface_layout;
StructuredBuffer<uint> interface_type_reverse_flag;
StructuredBuffer<uint> interface_type_reverse_prefix;
StructuredBuffer<uint> interface_type_edge_prefix;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> interface_member_index_by_generic_row;
StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_member_words;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
uint parameter_member(uint root, uint parameter, uint kind)
{
    uint row = lexical_parameter_row(root, parameter, kind);
    if (row >= min(generic_param_count_out[0u], gParams.token_capacity) || generic_param_token[row] != parameter) return INVALID;
    uint member = interface_member_index_by_generic_row[row];
    if (member >= interface_member_total[0u] ||
        interface_member_words[member * SEMANTIC_INTERFACE_MEMBER_WORDS] != interface_type_seed_owner[root] ||
        interface_member_words[member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u] != (kind == 1u ? 2u : 3u)) return INVALID;
    return member;
}
bool emit_type(uint root, uint index, uint2 ref, uint kind, uint first_edge, uint children)
{
    uint base = index * 9u;
    for (uint word = 0u; word < 9u; word++) interface_types[base + word] = 0u;
    interface_types[base] = kind;
    interface_types[base + 3u] = children == 0u ? 0u : first_edge;
    interface_types[base + 4u] = children;
    if (kind == 1u) interface_types[base + 1u] = ref.y;
    else if (kind == 9u)
    {
        uint3 value;
        if (!checked_constant_atom_value(ref.y, value) || !constant_value_is_valid(value)) return false;
        interface_types[base + 1u] = value.x;
        interface_types[base + 6u] = value.y;
        interface_types[base + 7u] = value.z;
    }
    else if (kind == 10u)
    {
        uint target;
        uint2 child;
        if (children != 1u || !checked_export_projection(ref.y, target, child)) return false;
        interface_types[base + 1u] = target;
    }
    else if (kind == 2u || kind == 8u)
    {
        uint member = parameter_member(root, ref.y, kind == 2u ? 1u : 2u);
        if (member == INVALID) return false;
        interface_types[base + 1u] = member;
    }
    else if (kind == 3u)
    {
        uint declaration = type_instance_decl_token[ref.y];
        uint library; uint unit; uint local;
        if (declaration < gParams.token_capacity)
        {
            uint source = decl_id_by_name_token[declaration];
            local = source < gParams.decl_capacity ? public_decl_index_by_local[source] : INVALID;
            library = gParams.library_id; unit = gParams.unit_id;
        }
        else
        {
            library = external_type_library_id[ref.y];
            unit = external_type_unit_id[ref.y];
            local = external_type_local_index[ref.y];
        }
        if (library == INVALID || unit == INVALID || local == INVALID) return false;
        interface_types[base + 1u] = library;
        interface_types[base + 2u] = local;
        interface_types[base + 8u] = unit;
    }
    return true;
}
// A root owns a disjoint interval. Preorder traversal assigns descending type
// indices, retaining the format's contiguous reverse-preorder trees.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (row >= active) return;
    uint count = interface_type_reverse_flag[row];
    if (count == 0u) return;
    uint root = active - 1u - row;
    uint start = interface_type_reverse_prefix[row];
    if (start >= gParams.hir_capacity || count > gParams.hir_capacity - start)
        { checked_export_fail(root, 2u); return; }
    uint2 refs[EXPORT_DEPTH_LIMIT];
    uint next[EXPORT_DEPTH_LIMIT]; uint children[EXPORT_DEPTH_LIMIT]; uint edge_start[EXPORT_DEPTH_LIMIT];
    uint depth = 0u; uint emitted = 0u;
    uint edge_cursor = interface_type_edge_prefix[row];
    uint edge_end = edge_cursor + count - 1u;
    refs[0u] = checked_export_root(root); next[0u] = INVALID;
    for (;;)
    {
        if (next[depth] == INVALID)
        {
            uint kind = checked_export_kind(refs[depth], children[depth]);
            if (kind == 0u || emitted >= count || edge_cursor > edge_end || children[depth] > edge_end - edge_cursor)
                { checked_export_fail(root, 3u); return; }
            uint index = start + count - 1u - emitted++;
            if (depth != 0u)
            {
                uint edge = edge_start[depth - 1u] + next[depth - 1u] - 1u;
                interface_type_edges[edge] = index;
                interface_type_edge_written[edge] = 1u;
            }
            edge_start[depth] = edge_cursor; edge_cursor += children[depth];
            if (!emit_type(root, index, refs[depth], kind, edge_start[depth], children[depth]))
                { checked_export_fail(root, 4u); return; }
            next[depth] = 0u;
        }
        if (next[depth] == children[depth])
        {
            if (depth == 0u) break;
            depth--; continue;
        }
        uint2 child;
        if (depth + 1u == EXPORT_DEPTH_LIMIT || !checked_export_child(refs[depth], next[depth]++, child))
            { checked_export_fail(root, 5u); return; }
        depth++; refs[depth] = child; next[depth] = INVALID;
    }
    if (emitted != count || edge_cursor != edge_end) checked_export_fail(root, 6u);
}
