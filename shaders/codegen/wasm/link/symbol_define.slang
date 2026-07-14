import codegen.wasm.link.common;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = tid.x;
    if (symbol_i >= gLink.symbol_count || link_symbol[symbol_i].w == INVALID) return;
    uint representative = lookup_identity(symbol_i);
    if (representative == INVALID) { fail(2u, symbol_i); return; }
    uint prior;
    InterlockedCompareExchange(link_symbol_definition[representative], INVALID, link_symbol[symbol_i].w, prior);
    if (prior != INVALID) fail(3u, symbol_i);
}
