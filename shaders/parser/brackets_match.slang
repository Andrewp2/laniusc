// shaders/parser/brackets_match.slang
// MVP: single-thread pass that validates the stack-change stream and builds
//      a match map (push<->pop). Later we can swap to a parallel O(log n) algo.

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

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0)
        return;
    const uint n = gParams.n_sc;

    // Clear outputs
    for (uint i = 0; i < n; ++i)
    {
        match_for_index[i] = 0xFFFFFFFF;
    }
    out_depths[0] = 0; // final
    out_depths[1] = 0; // min
    out_valid[0] = 1;

    // A tiny stack stored inside match_for_index as scratch space
    //   stack[top] holds a *push index*; we keep a separate top pointer.
    uint top = 0;

    int depth = 0;
    int min_depth = 0;

    // First pass: compute matches and depths
    for (uint i = 0; i < n; ++i)
    {
        uint code = sc_stream[i];
        bool is_push = (code & 1) == 1;

        if (is_push)
        {
            // push index onto temp stack region at [top]
            if (top < n)
            {
                match_for_index[top] = i; // use front of buffer as a scratch array
                top++;
            }
            depth++;
            if (depth < min_depth)
                min_depth = depth;
        }
        else
        {
            // pop
            if (depth <= 0 || top == 0)
            {
                // unbalanced close
                out_valid[0] = 0;
                depth--; // keep tracking depth/min for diagnostics
                if (depth < min_depth)
                    min_depth = depth;
                continue;
            }

            uint push_idx = match_for_index[top - 1];
            top--;
            depth--;
            if (depth < min_depth)
                min_depth = depth;

            // Optional typed check: require symbol IDs to match
            if (gParams.typed_check != 0)
            {
                uint push_sym = (sc_stream[push_idx] >> 1);
                uint pop_sym = (code >> 1);
                if (push_sym != pop_sym)
                {
                    out_valid[0] = 0;
                }
            }

            // Write final bi-directional match mapping
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
