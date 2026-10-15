// A replay seed owns semantic shape and optional prior width witnesses.
// Native publication requires each argument root to acquire a checked layout.
// Descendant referents need not have a value layout merely to store a pointer.
import primitive_types;
import status;
import type_checker.native_nominal_identity;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint4> body_specialization_inputs;
StructuredBuffer<uint4> checked_constant_atoms;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_native_word_count;
StructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> status;

#include "../../type/instances/body_type_graph_reference.slang"
#include "../../type/instances/body_specialization_entries.slang"

static const uint INVALID = 0xffffffffu;

uint root_words(uint tag, uint payload, uint capacity)
{
    if (tag == 1u && scalar_is_known(payload))
        return payload == SCALAR_STR ? 2u : 1u;
    if (tag == 1u)
    {
        uint token = native_nominal_token(payload, gParams.n_tokens, type_native_scalar_identity);
        return token != INVALID && token < capacity ? type_native_word_count[token] : INVALID;
    }
    return tag == 3u && payload < capacity ? type_native_word_count[payload] : INVALID;
}

// Lane t validates graph node t and argument slot t % 32 of entry t / 32.
// The host dispatches BODY_MAX_ENTRIES * BODY_TYPE_SLOTS lanes.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x;
    if (dtid.y != 0u || dtid.z != 0u) return;
    uint4 header = body_specialization_inputs[0u];
    if (header.x > BODY_TYPE_SLOTS || header.z > BODY_GRAPH_NODES)
    {
        if (lane == 0u) record_min_token_error(status, 0u, 6u, 0x474e0008u);
        return;
    }
    uint source_capacity; uint stride; uint capacity;
    type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
    type_native_word_count.GetDimensions(capacity, stride);
    if (source_capacity > capacity || header.z > capacity - source_capacity)
    {
        if (lane == 0u) record_min_token_error(status, 0u, 6u, 0x474e0008u);
        return;
    }
    if (lane < header.z)
    {
        uint4 node = body_graph_node(lane);
        // Primitive and constant packet leaves have no compound width column.
        // Known compound witnesses must agree with the late native producer.
        if ((node.x == 2u || node.x == 3u || node.x == 4u || node.x == 9u) &&
            node.w != INVALID)
        {
            uint tag; uint payload;
            body_type_graph_reference(lane, source_capacity, tag, payload);
            uint derived = root_words(tag, payload, capacity);
            if (derived != node.w)
                record_min_token_error(status, 0u, 6u, 0x474e0007u);
        }
    }
    // Every entry's argument roots (entry 0's header was checked above).
    uint entry = lane / BODY_TYPE_SLOTS;
    uint slot = lane % BODY_TYPE_SLOTS;
    if (entry >= body_entry_count()) return;
    // 00d2 must have resolved every instance copy to its function row.
    if (slot == 0u && body_entry_copy_byte(entry) != INVALID &&
        ((body_entry_header(entry).y & 0xc0000000u) != 0x80000000u ||
            (body_entry_header(entry).y & 0x7fffffffu) < body_copy_first_row()))
        record_min_token_error(status, 0u, 6u, 0x474e0009u);
    uint arguments = body_entry_header(entry).x;
    if (arguments > BODY_TYPE_SLOTS)
    { if (slot == 0u) record_min_token_error(status, 0u, 6u, 0x474e0008u); return; }
    if (slot >= arguments) return;
    uint4 argument = body_entry_argument(entry, slot);
    if (argument.x != slot || argument.y != 10u || argument.z >= header.z)
    { record_min_token_error(status, 0u, 6u, 0x474e0008u); return; }
    uint tag; uint payload;
    body_type_graph_reference(argument.z, source_capacity, tag, payload);
    uint width = root_words(tag, payload, capacity);
    if (width == INVALID) record_min_token_error(status, 0u, 6u, 0x474e0006u);
    else if (width > 0xffffu) record_min_token_error(status, 0u, 6u, 0x474e0008u);
}
