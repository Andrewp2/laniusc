// One lane per object: validates the dense transfer layout and publishes the
// output demand (end of the last object's symbol and identity ranges).

import codegen.x86.finalize.symbol_finalize_common;

// (symbol start, symbol count, identity word start, identity byte length)
StructuredBuffer<uint4> fin_objects;
RWStructuredBuffer<uint> fin_status;

uint identity_words(uint byte_len)
{
    return (byte_len >> 2u) + ((byte_len & 3u) != 0u ? 1u : 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint object_i = finalize_lane(tid);
    if (object_i >= gFinalize.object_count)
        return;
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
