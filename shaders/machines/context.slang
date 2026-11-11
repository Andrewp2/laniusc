// Per token: whether an arm of a state, a field or an argument of a `goto`
// starts here. A `match` inside a block arm has arms of its own, and a call
// inside an argument has arguments of its own: the bracket depth tells them
// from the state's arms and the transition's arguments.
import gpu_index;
import machine_common;

struct ContextParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ContextParams> gContext;
StructuredBuffer<uint> records;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint> states;
StructuredBuffer<uint> transitions;
RWStructuredBuffer<uint4> marks;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * REC_WORDS + word];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gContext.token_count)
        return;
    uint role = rec(token, REC_ROLE);
    uint4 sums = scan_a[token];
    uint depth_before = token > 0u ? scan_a[token - 1u].w : 0u;

    bool arm = false;
    if (role == ROLE_ARM && sums.y > 0u)
    {
        uint state = states[sums.y - 1u];
        uint block = rec(state, REC_BLOCK);
        arm = token > block && token < rec(state, REC_END) && depth_before == scan_a[block].w;
    }
    bool argument = false;
    if (role == ROLE_ARGUMENT && sums.z > 0u)
    {
        uint transition = transitions[sums.z - 1u];
        uint close = rec(transition, REC_ARGS_CLOSE);
        uint open = transition + 2u;
        argument = close != 0u && token > open && token < close && depth_before == scan_a[open].w;
    }
    bool field = role == ROLE_FIELD || role == ROLE_DATA;
    marks[token] = uint4(arm ? 1u : 0u, field ? 1u : 0u, argument ? 1u : 0u, 0u);
}
