// Entries of a body specialization packet (CheckedBodySpecializationBatch).
// Entry 0 uses the single-entry rows: header row 0 = (argument count, target,
// node count, edge count), type slots at rows 1 + 2 * slot, constant rows at
// 706 + slot = (slot, scalar, lo, hi) and row 705.x = constant count. Row
// 705.y counts extra entries. Extra entry e (1-based) has 65 rows from
// 738 + (e - 1) * 65: header (argument count, target, 0, constant count),
// type slots (slot, 10, root, 0) and constant slots (slot, 10, node, 0) whose
// value is a kind-10 node of the shared graph. Requires body_specialization_inputs.

static const uint BODY_MAX_ENTRIES = 64u;
static const uint BODY_EXTRA_ENTRY_START = 738u;
static const uint BODY_EXTRA_ENTRY_ROWS = 65u;

uint body_extra_entry_row(uint entry)
{
    return BODY_EXTRA_ENTRY_START + (entry - 1u) * BODY_EXTRA_ENTRY_ROWS;
}

// Zero outside replay. Every entry has a nonempty environment, so entry 0
// exists exactly when its header or constant count is nonzero.
uint body_entry_count()
{
    bool present = body_specialization_inputs[0u].x != 0u || body_specialization_inputs[705u].x != 0u;
    return present ? 1u + min(body_specialization_inputs[705u].y, BODY_MAX_ENTRIES - 1u) : 0u;
}

// (argument count, target symbol, 0, constant count)
uint4 body_entry_header(uint entry)
{
    if (entry == 0u)
        return uint4(body_specialization_inputs[0u].xy, 0u, body_specialization_inputs[705u].x);
    return body_specialization_inputs[body_extra_entry_row(entry)];
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
        atom = atom_base + 64u + slot;
        return binding.x == slot;
    }
    uint4 binding = body_specialization_inputs[body_extra_entry_row(entry) + 33u + slot];
    uint nodes = min(body_specialization_inputs[0u].z, 64u);
    if (binding.x != slot || binding.y != 10u || binding.z >= nodes) return false;
    uint4 node = body_specialization_inputs[65u + binding.z * 2u];
    value = uint3(node.y, node.z, body_specialization_inputs[66u + binding.z * 2u].x);
    atom = atom_base + binding.z;
    return node.x == 10u;
}
