// Entries of a body specialization packet (CheckedBodySpecializationBatch).
// Entry 0 uses the single-entry rows: header row 0 = (argument count, target,
// node count, edge count), type slots at rows 1 + 2 * slot, constant rows at
// 706 + slot = (slot, scalar, lo, hi) and row 705.x = constant count. Row
// 705.y counts extra entries; 705.z is entry 0's copy word and 705.w the
// first copy row (see body_entry_copy_byte). A graph larger than the
// single-entry capacity continues in BODY_GRAPH_EXT_ROWS rows from 738
// (body_graph_rows.slang). Extra entry e (1-based) then has 65 rows from
// 738 + extension rows + (e - 1) * 65: header (argument count, target, copy
// word, constant count), type slots (slot, 10, root, 0) and constant slots
// (slot, 10, node, 0) whose value is a kind-10 node of the shared graph.
// Requires body_specialization_inputs.
#ifndef LANIUS_BODY_SPECIALIZATION_ENTRIES
#define LANIUS_BODY_SPECIALIZATION_ENTRIES
#include "body_graph_rows.slang"

static const uint BODY_EXTRA_ENTRY_ROWS = 65u;

uint body_extra_entry_row(uint entry)
{
    return BODY_GRAPH_EXT_START + body_graph_extension_rows() + (entry - 1u) * BODY_EXTRA_ENTRY_ROWS;
}

// Zero outside replay. Every entry has a nonempty environment, so entry 0
// exists exactly when its header or constant count is nonzero.
uint body_entry_count()
{
    bool present = body_specialization_inputs[0u].x != 0u || body_specialization_inputs[705u].x != 0u;
    return present ? 1u + min(body_specialization_inputs[705u].y, BODY_MAX_ENTRIES - 1u) : 0u;
}

// (argument count, target symbol, copy word, constant count)
uint4 body_entry_header(uint entry)
{
    if (entry == 0u)
        return uint4(body_specialization_inputs[0u].xy, body_specialization_inputs[705u].z,
            body_specialization_inputs[705u].x);
    return body_specialization_inputs[body_extra_entry_row(entry)];
}

// Instance-copy replay: the source byte of the entry's copied `fn` keyword,
// stored plus one in the copy word (705.z for entry 0, header .z otherwise);
// INVALID for an entry that replays its original declaration. Copy bytes
// increase with the entry index. 00d2 resolves the target from it.
uint body_entry_copy_byte(uint entry)
{
    uint word = body_entry_header(entry).z;
    return word == 0u ? 0xffffffffu : word - 1u;
}

// The first HIR row after the template: every copy row is at or past it.
// Bit 31 of 705.w marks a declarations-only template (returns/03_validate).
uint body_copy_first_row()
{
    return body_specialization_inputs[705u].w & 0x7fffffffu;
}

// (slot, 10, shared root, 0)
uint4 body_entry_argument(uint entry, uint slot)
{
    return entry == 0u ? body_specialization_inputs[slot * 2u + 1u]
        : body_specialization_inputs[body_extra_entry_row(entry) + 1u + slot];
}

// The checked value (scalar, lo, hi) of one constant slot and the reserved
// atom row that holds it. False for a malformed row.
bool body_entry_constant(uint entry, uint slot, uint atom_base, out uint3 value, out uint atom)
{
    value = uint3(0u, 0u, 0u);
    atom = 0xffffffffu;
    if (entry == 0u)
    {
        uint4 binding = body_specialization_inputs[706u + slot];
        value = binding.yzw;
        atom = atom_base + BODY_GRAPH_NODES + slot;
        return binding.x == slot;
    }
    uint4 binding = body_specialization_inputs[body_extra_entry_row(entry) + 1u + BODY_TYPE_SLOTS + slot];
    if (binding.x != slot || binding.y != 10u || binding.z >= body_graph_node_count()) return false;
    uint4 node = body_graph_node(binding.z);
    value = uint3(node.y, node.z, body_graph_identity(binding.z).x);
    atom = atom_base + binding.z;
    return node.x == 10u;
}

#endif
