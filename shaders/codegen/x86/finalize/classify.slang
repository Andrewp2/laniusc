// One lane per symbol. A provisional symbol takes its route's final identity
// and claims the three identity words it will rewrite. Its route row must be
// written for this build and name a final identity (an instance rank below
// the readiness instance count, or a DeclNative identity); routes are flat,
// so a row never names another use. Rows no symbol names are not read. Every other symbol
// marks the words its identity bytes cover as preserved; its bytes and hash
// are copied unchanged.

import codegen.x86.finalize.symbol_finalize_common;

StructuredBuffer<uint4> fin_readiness;
StructuredBuffer<uint4> fin_routes;
StructuredBuffer<uint4> fin_objects;
StructuredBuffer<uint> fin_symbols_in;
StructuredBuffer<uint> fin_identity_in;
RWStructuredBuffer<uint> fin_word_owner;
RWStructuredBuffer<uint> fin_word_preserved;
// (final identity, first rewritten identity word or INVALID)
RWStructuredBuffer<uint4> fin_symbol_final;
RWStructuredBuffer<uint> fin_status;

void fail(uint code, uint detail)
{
    InterlockedMin(fin_status[failure_slot(code)], detail);
}

uint object_of_symbol(uint symbol_i)
{
    // Largest object whose symbol range starts at or before this symbol.
    uint low = 0u;
    uint high = gFinalize.object_count;
    while (high - low > 1u)
    {
        uint middle = low + (high - low) / 2u;
        if (fin_objects[middle].x <= symbol_i)
            low = middle;
        else
            high = middle;
    }
    return low;
}

uint identity_byte(uint byte_index)
{
    return (fin_identity_in[byte_index >> 2u] >> ((byte_index & 3u) * 8u)) & 0xffu;
}

uint identity_word_at(uint byte_index)
{
    uint word = 0u;
    for (uint i = 0u; i < 4u; i += 1u)
        word |= identity_byte(byte_index + i) << (i * 8u);
    return word;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = finalize_lane(tid);
    if (symbol_i >= gFinalize.symbol_count)
        return;
    fin_symbol_final[symbol_i] = uint4(0u, 0u, 0u, INVALID);
    if (gFinalize.object_count == 0u)
    {
        fail(FAIL_OBJECT_MALFORMED, 0u);
        return;
    }
    uint4 object = fin_objects[object_of_symbol(symbol_i)];
    uint row = symbol_i * SYMBOL_WORDS;
    uint start = fin_symbols_in[row + 2u];
    uint len = fin_symbols_in[row + 3u];
    if (len == 0u || start > object.w || len > object.w - start)
    {
        fail(FAIL_SYMBOL_MALFORMED, symbol_i);
        return;
    }
    uint byte_base = object.z * 4u + start;
    bool provisional = false;
    if (len == PROVISIONAL_IDENTITY_BYTES)
    {
        provisional = identity_word_at(byte_base) == RESERVED_LIB &&
            identity_word_at(byte_base + 4u) == NS_USE;
    }
    if (!provisional)
    {
        uint first_word = byte_base >> 2u;
        uint last_word = (byte_base + len - 1u) >> 2u;
        for (uint word = first_word; word <= last_word; word += 1u)
            fin_word_preserved[word] = 1u;
        return;
    }
    // The emitter writes each provisional identity as three aligned words.
    uint3 identity = uint3(RESERVED_LIB, NS_USE, identity_word_at(byte_base + 8u));
    if ((byte_base & 3u) != 0u ||
        any(identity_hash(identity) != uint2(fin_symbols_in[row], fin_symbols_in[row + 1u])))
    {
        fail(FAIL_SYMBOL_MALFORMED, symbol_i);
        return;
    }
    if (fin_symbols_in[row + 4u] != SECTION_UNDEFINED)
    {
        fail(FAIL_PROVISIONAL_DEFINITION, symbol_i);
        return;
    }
    uint use_i = identity.z;
    if (use_i >= min(fin_readiness[0u].w, gFinalize.route_capacity))
    {
        fail(FAIL_USE_OUT_OF_RANGE, symbol_i);
        return;
    }
    uint4 route = fin_routes[use_i];
    if (route.w != gFinalize.generation)
    {
        fail(FAIL_ROUTE_MISSING, use_i);
        return;
    }
    if (route.x == OBJECT_LOCAL)
    {
        fail(FAIL_ROUTE_INVALID_IDENTITY, use_i);
        return;
    }
    if (route.x == RESERVED_LIB)
    {
        if (route.y == NS_USE)
        {
            fail(FAIL_ROUTE_USE_CHAIN, use_i);
            return;
        }
        if (route.y != NS_INSTANCE)
        {
            fail(FAIL_ROUTE_INVALID_IDENTITY, use_i);
            return;
        }
        if (route.z >= fin_readiness[0u].z)
        {
            fail(FAIL_ROUTE_OUT_OF_RANGE, use_i);
            return;
        }
    }
    uint word_base = byte_base >> 2u;
    fin_symbol_final[symbol_i] = uint4(route.xyz, word_base);
    for (uint i = 0u; i < 3u; i += 1u)
        InterlockedMin(fin_word_owner[word_base + i], symbol_i);
}
