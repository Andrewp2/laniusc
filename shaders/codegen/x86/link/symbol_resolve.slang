// Resolve every symbol row to the unique definition for its exact 96-bit identity.

import atomics;
import gpu_index;

struct Params
{
    uint symbol_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> link_symbol_identity_section;
StructuredBuffer<uint> link_symbol_order;
RWStructuredBuffer<uint> link_symbol_definition;
RWStructuredBuffer<uint> link_symbol_status;

static const uint INVALID = 0xffffffffu;
static const uint X86_LINK_DUPLICATE_SYMBOL = 1u;

bool identity_equal(uint4 left, uint4 right)
{
    return all(left.xyz == right.xyz);
}

bool identity_less(uint4 left, uint4 right)
{
    if (left.z != right.z)
        return left.z < right.z;
    if (left.y != right.y)
        return left.y < right.y;
    return left.x < right.x;
}

uint lower_bound_identity(uint4 identity)
{
    uint lo = 0u;
    uint hi = gParams.symbol_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint row = link_symbol_order[mid];
        if (identity_less(link_symbol_identity_section[row], identity))
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

void publish_duplicate(uint symbol_i)
{
    atomic_u32_min(link_symbol_status, 2u, symbol_i);
    link_symbol_status[0u] = 0u;
    link_symbol_status[1u] = X86_LINK_DUPLICATE_SYMBOL;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (symbol_i >= gParams.symbol_count)
        return;

    uint4 identity = link_symbol_identity_section[symbol_i];
    uint sorted_i = lower_bound_identity(identity);
    uint definition = INVALID;
    if (sorted_i < gParams.symbol_count)
    {
        uint candidate = link_symbol_order[sorted_i];
        uint4 candidate_record = link_symbol_identity_section[candidate];
        if (identity_equal(candidate_record, identity) && candidate_record.w != 0u)
        {
            definition = candidate;
            if (sorted_i + 1u < gParams.symbol_count)
            {
                uint next = link_symbol_order[sorted_i + 1u];
                uint4 next_record = link_symbol_identity_section[next];
                if (identity_equal(next_record, identity) && next_record.w != 0u)
                    publish_duplicate(min(candidate, next));
            }
        }
    }
    link_symbol_definition[symbol_i] = definition;
}
