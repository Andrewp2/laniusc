// Per state: the rules of a whole state. Its arms handle every event: each
// variant of an enum, or every integer through a last arm that accepts any.
// It is reachable from the start state, and it has a `goto` to another state
// unless it is `final`.
import gpu_index;
import machine_common;

struct StateParams
{
    uint state_count;
    uint reserved0;
    uint explain_word;
    uint explain_key;
};

ConstantBuffer<StateParams> gStates;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint4> scan_b;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> states;
StructuredBuffer<uint> variants;
StructuredBuffer<uint> machine_info;
StructuredBuffer<uint> arm_event;
// Per state, two rows of four words: the states its `goto`s name, and the
// states reachable from it.
StructuredBuffer<uint4> adjacency;
StructuredBuffer<uint4> reach;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> detail;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * REC_WORDS + word];
}

void raise(uint word, uint token, uint code, uint a, uint b)
{
    machine_error(status, detail, tokens_out, gStates.explain_word, gStates.explain_key, word, token, code, a, b, 0u);
}

uint4 bit_row(uint index, uint half)
{
    uint word = index >> 5u;
    if ((word >> 2u) != half)
        return uint4(0u, 0u, 0u, 0u);
    uint bit = 1u << (index & 31u);
    uint part = word & 3u;
    return uint4(part == 0u ? bit : 0u, part == 1u ? bit : 0u, part == 2u ? bit : 0u, part == 3u ? bit : 0u);
}

bool any_bit(uint4 row)
{
    return (row.x | row.y | row.z | row.w) != 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (i >= gStates.state_count)
        return;
    uint state = states[i];
    uint name = state + 1u;
    uint ordinal = scan_a[state].x - 1u;
    uint head = machines[ordinal];
    uint info = ordinal * INFO_WORDS;
    uint event_enum = machine_info[info + INFO_ENUM];
    uint start = machine_info[info + INFO_START];

    // The state's arms are the slots `[first_arm, end_arm)`.
    uint first_arm = scan_b[rec(state, REC_BLOCK)].x;
    uint end_arm = scan_b[rec(state, REC_END) - 1u].x;
    if (machine_info[info + INFO_INTEGER] != 0u)
    {
        if (end_arm == first_arm || arm_event[end_arm - 1u] == 0u)
            raise(STATUS_EVENTS, name, E_CATCH_ALL, 0u, 0u);
    }
    else if (event_enum != 0u)
    {
        uint first = scan_b[event_enum].w;
        uint count = min(scan_b[rec(event_enum, REC_END) - 1u].w - first, MAX_LIST);
        uint arm_count = min(end_arm - first_arm, MAX_LIST);
        bool output = (rec(head, REC_FLAGS) & FLAG_OUTPUT) != 0u;
        for (uint v = 0u; v < count; v += 1u)
        {
            bool handled = false;
            for (uint k = 0u; k < arm_count && !handled; k += 1u)
                handled = arm_event[first_arm + k] == v + 1u;
            if (!handled)
            {
                raise(STATUS_EVENTS, name, output ? E_MISSING_EVENT_OUTPUT : E_MISSING_EVENT, head + 3u,
                      variants[first + v]);
                break;
            }
        }
    }

    if (start == 0u)
        return;
    uint first_state = scan_a[head].y;
    uint index = i - first_state;
    uint start_ordinal = scan_a[start].y - 1u;
    uint start_index = start_ordinal - first_state;
    if (index >= MAX_STATES || start_index >= MAX_STATES)
        return;
    uint4 own_low = bit_row(index, 0u);
    uint4 own_high = bit_row(index, 1u);
    bool reached = index == start_index || any_bit(reach[start_ordinal * 2u] & own_low) ||
                   any_bit(reach[start_ordinal * 2u + 1u] & own_high);
    bool leaves = any_bit(adjacency[i * 2u] & ~own_low) || any_bit(adjacency[i * 2u + 1u] & ~own_high);
    bool is_final = (rec(state, REC_FLAGS) & FLAG_FINAL) != 0u;
    if (!reached)
        raise(STATUS_GRAPH, name, E_UNREACHABLE, rec(head, REC_START), 0u);
    else if (!leaves && !is_final)
        raise(STATUS_GRAPH, name, E_DEAD_END, 0u, 0u);
    else if (leaves && is_final)
        raise(STATUS_GRAPH, name, E_FINAL_LEAVES, 0u, 0u);
}
