import codegen.x86.symbol_finalization.symbol_finalization_layout;
import codegen.x86.symbol_finalization.symbol_publication_predicate;

RWStructuredBuffer<uint> fin_word_owner;
RWStructuredBuffer<uint> fin_word_preserved;
public RWStructuredBuffer<uint> fin_status;
StructuredBuffer<uint4> fin_objects;
StructuredBuffer<uint4> fin_readiness;
StructuredBuffer<uint4> fin_routes;
StructuredBuffer<uint> fin_symbols_in;
StructuredBuffer<uint> fin_identity_in;
RWStructuredBuffer<uint4> fin_symbol_final;
RWStructuredBuffer<uint> fin_symbols_out;
RWStructuredBuffer<uint> fin_identity_out;

uint identity_words(uint byte_len)
{
    return (byte_len >> 2u) + ((byte_len & 3u) != 0u ? 1u : 0u);
}

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

public void clear_finalize_row(uint i)
{
    if (i < gFinalize.identity_word_count)
    {
        fin_word_owner[i] = INVALID;
        fin_word_preserved[i] = 0u;
    }
    if (i < STATUS_WORDS)
        fin_status[i] = i >= STATUS_FAILURE_BASE ? INVALID : 0u;
}

public void validate_object_range(uint object_i)
{
    uint4 object = fin_objects[object_i];
    uint symbol_end = object.x + object.y;
    uint word_end = object.z + identity_words(object.w);
    bool valid = symbol_end >= object.x && word_end >= object.z &&
        symbol_end <= gFinalize.symbol_count && word_end <= gFinalize.identity_word_count;
    if (object_i == 0u)
        valid = valid && object.x == 0u && object.z == 0u;
    else
    {
        uint4 previous = fin_objects[object_i - 1u];
        valid = valid && object.x == previous.x + previous.y &&
            object.z == previous.z + identity_words(previous.w);
    }
    if (object_i + 1u == gFinalize.object_count)
    {
        valid = valid && symbol_end == gFinalize.symbol_count &&
            word_end == gFinalize.identity_word_count;
        fin_status[STATUS_SYMBOL_DEMAND] = symbol_end;
        fin_status[STATUS_IDENTITY_DEMAND] = word_end;
    }
    if (!valid)
        InterlockedMin(fin_status[failure_slot(FAIL_OBJECT_MALFORMED)], object_i);
}

public void check_route_readiness()
{
    uint4 readiness = fin_readiness[0u];
    if (readiness.x != gFinalize.generation)
        fail(FAIL_READINESS, READINESS_GENERATION);
    if ((readiness.y & READY_ROUTES_PUBLISHED) == 0u)
        fail(FAIL_READINESS, READINESS_ROUTES_UNPUBLISHED);
    if ((readiness.y & READY_ABI_CERTIFIED) == 0u)
        fail(FAIL_READINESS, READINESS_ABI_UNCERTIFIED);
    if (readiness.w > gFinalize.route_capacity)
        fail(FAIL_READINESS, READINESS_ROUTE_TABLE_SHORT);
}

public void claim_symbol_words(uint symbol_i)
{
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

public void check_symbol_claims(uint symbol_i)
{
    uint word_base = fin_symbol_final[symbol_i].w;
    if (word_base == INVALID)
        return;
    for (uint i = 0u; i < 3u; i += 1u)
    {
        uint owner = fin_word_owner[word_base + i];
        if (fin_word_preserved[word_base + i] != 0u || owner == INVALID ||
            fin_symbol_final[owner].w != word_base)
        {
            InterlockedMin(fin_status[failure_slot(FAIL_IDENTITY_OVERLAP)], symbol_i);
            return;
        }
    }
}

public void publish_symbol(uint symbol_i)
{
    uint row = symbol_i * SYMBOL_WORDS;
    uint4 final_identity = fin_symbol_final[symbol_i];
    uint2 hash = final_identity.w == INVALID
        ? uint2(fin_symbols_in[row], fin_symbols_in[row + 1u])
        : identity_hash(final_identity.xyz);
    fin_symbols_out[row] = hash.x;
    fin_symbols_out[row + 1u] = hash.y;
    for (uint i = 2u; i < SYMBOL_WORDS; i += 1u)
        fin_symbols_out[row + i] = fin_symbols_in[row + i];
}

public void publish_identity_word(uint word)
{
    uint owner = fin_word_owner[word];
    if (owner == INVALID)
    {
        fin_identity_out[word] = fin_identity_in[word];
        return;
    }
    uint4 final_identity = fin_symbol_final[owner];
    fin_identity_out[word] = final_identity[word - final_identity.w];
}
