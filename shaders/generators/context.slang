// Per token: whether a parameter or a local of a generator starts here, the
// change in the number of locals in scope, and the change of depth in the
// loops that hold a `yield`. The prefix sums give, at a `yield`, the number
// of locals in scope, and at a local, its position among them.
import gpu_index;
import generator_common;

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
// Inclusive prefix sums: generators, yields, loop depth, statement depth.
StructuredBuffer<uint4> scan1;
StructuredBuffer<uint> gens;
// Per `}`: the locals its block declares.
StructuredBuffer<uint> direct;
RWStructuredBuffer<uint4> marks;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * GR_WORDS + word];
}

// Whether the `while` body that opens at `open` holds a `yield`.
bool yields(uint open)
{
    return rec(open, GR_KIND) == BK_WHILE && scan1[rec(open, GR_END) - 1u].y != scan1[open].y;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gContext.token_count)
        return;
    uint role = rec(token, GR_ROLE);
    GenPlace place = gen_place(records, scan_a, scan1, gens, token);

    // A parameter of a generator sits between `gen` and the `)` of the
    // parameters, at their depth.
    bool param = false;
    if (role == GROLE_PARAM && place.gen != GN_NONE)
    {
        uint close = rec(place.gen, GR_OWNER);
        param = token < close && scan_a[token].w == scan_a[close].w + 1u;
    }
    bool local = role == GROLE_LET && place.eligible;
    uint scope = local ? 1u : 0u;
    uint loops = 0u;
    if (role == GROLE_BLOCK && yields(token))
        loops = 1u;
    if (role == GROLE_CLOSE)
    {
        scope = 0u - direct[token];
        if (yields(rec(token, GR_OPEN)))
            loops = 0xffffffffu;
    }
    marks[token] = uint4(param ? 1u : 0u, local ? 1u : 0u, scope, loops);
}
