import constant_value;
import primitive_types;
import status;

// A single producer recreates the retained checked graph in a private arena.
// Its IDs follow the entire source-token capacity, so declaration-side rows
// and lexical references are immutable and cannot collide with replay nodes.
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint4> body_specialization_inputs;
RWStructuredBuffer<uint4> checked_constant_atoms;
RWStructuredBuffer<uint> status;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_row_start;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_native_word_count;
RWStructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;

#include "body_type_graph_reference.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u, 0u, 0u))) return;
    static const uint INVALID = 0xffffffffu;
    uint count = min(body_specialization_inputs[0u].z, 64u);
    uint constant_count = min(body_specialization_inputs[705u].x, 32u);
    if (count == 0u && constant_count == 0u) return;
    uint atom_base = body_constant_atom_base();
    if (atom_base == INVALID)
    { record_min_token_error(status, 0u, 6u, 0x474e0008u); return; }
    for (uint row = 0u; row < 96u; row++)
        checked_constant_atoms[atom_base + row] = uint4(0u, 0u, 0u, 0u);
    for (uint slot = 0u; slot < constant_count; slot++)
    {
        uint4 binding = body_specialization_inputs[706u + slot];
        if (binding.x != slot || !constant_value_is_valid(binding.yzw))
        { record_min_token_error(status, 0u, 6u, 0x474e0008u); return; }
        checked_constant_atoms[atom_base + 64u + slot] = uint4(binding.yzw, 0u);
    }
    uint source_capacity; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint4 node = body_specialization_inputs[65u + ordinal * 2u];
        uint4 identity = body_specialization_inputs[66u + ordinal * 2u];
        uint instance = source_capacity + ordinal;
        if (node.x == 10u)
        {
            uint3 value = uint3(node.y, node.z, identity.x);
            if (!constant_value_is_valid(value))
            { record_min_token_error(status, 0u, 6u, 0x474e0008u); return; }
            checked_constant_atoms[atom_base + ordinal] = uint4(value, 0u);
        }
        else if (node.x == 2u)
            checked_constant_atoms[atom_base + ordinal] = uint4(SCALAR_U32, node.z, 0u, 0u);
        type_instance_kind[instance] = node.x == 9u ? 1u : node.x == 1u || node.x == 10u ? 0u : node.x;
        type_instance_decl_token[instance] = node.x == 9u &&
            (identity.w & 0xe0000000u) == 0x20000000u
            ? identity.w & 0x1fffffffu : INVALID;
        type_instance_arg_count[instance] = node.x == 9u ? node.z : 0u;
        type_instance_arg_start[instance] = node.x == 9u
            ? source_capacity * 4u + ordinal * 32u : INVALID;
        type_instance_arg_row_start[instance] = INVALID;
        uint type_prefix = 0u; uint domain_flags = 0u; uint constant_positions = 0u; bool saw_constant = false;
        if (node.x == 9u)
        {
            for (uint slot = 0u; slot < node.z; slot++)
            {
                uint edge = node.y + slot;
                uint4 packed = body_specialization_inputs[193u + edge / 4u];
                uint child = packed[edge % 4u];
                uint start = type_instance_arg_start[instance];
                uint tag; uint payload;
                body_type_graph_reference(child, source_capacity, tag, payload);
                if ((tag & 0x80000000u) == 0u)
                { type_prefix++; if (saw_constant) domain_flags = 0x80000000u; }
                else { saw_constant = true; constant_positions |= 1u << slot; }
                type_instance_arg_ref_tag[start + slot] = tag;
                type_instance_arg_ref_payload[start + slot] = payload;
            }
        }
        type_instance_elem_ref_tag[instance] = 0u;
        type_instance_elem_ref_payload[instance] = INVALID;
        if (node.x == 2u || node.x == 3u || node.x == 4u)
        {
            uint tag; uint payload;
            body_type_graph_reference(node.y, source_capacity, tag, payload);
            type_instance_elem_ref_tag[instance] = tag;
            type_instance_elem_ref_payload[instance] = payload;
        }
        type_instance_len_kind[instance] = node.x == 2u ? 1u : node.x == 9u ? type_prefix | domain_flags : 0u;
        type_instance_len_payload[instance] = node.x == 2u ? atom_base + ordinal : node.x == 9u ? constant_positions : INVALID;
        // The aggregate cache uses zero for a provisional unknown, matching
        // ordinary application allocation. Native layout has its own explicit
        // INVALID state and is published by the late layout producer.
        type_instance_aggregate_word_count[instance] = node.w == INVALID ? 0u : node.w;
        type_native_word_count[instance] = INVALID;
        type_native_scalar_identity[instance] = 0u;
        type_instance_state[instance] = 1u;
        external_type_library_id[instance] = node.x == 9u ? identity.x : INVALID;
        external_type_unit_id[instance] = node.x == 9u ? identity.y : INVALID;
        external_type_local_index[instance] = node.x == 9u ? identity.z : INVALID;
    }
}
