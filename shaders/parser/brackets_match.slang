// shaders/parser/brackets_match.slang
// Validates the stack-change stream and builds a bi-directional match map.

struct Params
{
    uint n_sc;        // length of sc_stream
    uint typed_check; // 0 = ignore symbol IDs, 1 = require push/pop ID match
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;         // len = n_sc
RWStructuredBuffer<uint> match_for_index; // len = n_sc, 0xFFFFFFFF = unset

// depths[0] = final_depth, depths[1] = min_depth
RWStructuredBuffer<int> out_depths; // len = 2
RWStructuredBuffer<uint> out_valid; // len = 1, 1=valid, 0=invalid

// Dedicated stack of *push indices* (size = n_sc)
RWStructuredBuffer<uint> open_stack; // len = n_sc

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0)
        return;
    const uint n = gParams.n_sc;

    // Initialize outputs and stack
    for (uint i = 0; i < n; ++i)
    {
        match_for_index[i] = 0xFFFFFFFFu;
        open_stack[i] = 0xFFFFFFFFu;
    }
    out_depths[0] = 0; // final
    out_depths[1] = 0; // min
    out_valid[0] = 1;

    uint top = 0; // number of items on stack
    int depth = 0;
    int min_depth = 0;

    // Single-thread sweep (correct for any n, no fixed caps)
    for (uint i = 0; i < n; ++i)
    {
        uint code = sc_stream[i];
        bool is_push = (code & 1u) == 1u;

        if (is_push)
        {
            // Push index onto dedicated stack
            open_stack[top] = i;
            top++;

            depth++;
            if (depth < min_depth)
                min_depth = depth;
        }
        else
        {
            // Pop
            if (depth <= 0 || top == 0)
            {
                // Unbalanced close — still track depth for diagnostics
                out_valid[0] = 0;
                depth--;
                if (depth < min_depth)
                    min_depth = depth;
                continue;
            }

            uint push_idx = open_stack[top - 1u];
            top--;
            depth--;
            if (depth < min_depth)
                min_depth = depth;

            // Optional typed check: require symbol IDs to match
            if (gParams.typed_check != 0)
            {
                uint push_sym = (sc_stream[push_idx] >> 1u);
                uint pop_sym = (code >> 1u);
                if (push_sym != pop_sym)
                {
                    out_valid[0] = 0;
                }
            }

            // Write bi-directional match mapping
            match_for_index[push_idx] = i;
            match_for_index[i] = push_idx;
        }
    }

    if (top != 0)
    {
        // leftover opens
        out_valid[0] = 0;
    }

    out_depths[0] = depth;     // final_depth
    out_depths[1] = min_depth; // min_depth
}
