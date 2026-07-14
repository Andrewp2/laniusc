import codegen.wasm.link.common;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = tid.x;
    if (symbol_i >= gLink.symbol_count) return;
    uint mask = gLink.hash_capacity - 1u;
    uint slot = identity_hash(link_symbol[symbol_i].xyz) & mask;
    for (uint probe = 0u; probe < gLink.hash_capacity; probe += 1u)
    {
        uint prior;
        InterlockedCompareExchange(link_hash_table[slot], INVALID, symbol_i, prior);
        if (prior == INVALID || same_identity(prior, symbol_i)) return;
        slot = (slot + 1u) & mask;
    }
    fail(1u, symbol_i);
}
