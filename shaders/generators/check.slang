// Per token: the rules of a generator, and the counts the text is laid out
// from. A `yield` reserves one slot per local in scope, a local one pair per
// `yield` it is in scope of, and a `yield`, the `;` after it and a `return`
// count the pieces that replace them in a copy of the body.
import gpu_index;
import generated_token_ids;
import generator_common;

struct CheckParams
{
    uint token_count;
    uint reserved0;
    uint explain_word;
    uint explain_key;
};

ConstantBuffer<CheckParams> gCheck;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> records;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
// Inclusive prefix sums: generators, yields, loop depth, statement depth.
StructuredBuffer<uint4> scan1;
// Inclusive prefix sums: parameters, locals, locals in scope, depth in the
// loops that hold a `yield`.
StructuredBuffer<uint4> scan2;
StructuredBuffer<uint> gens;
StructuredBuffer<uint> params;
StructuredBuffer<uint> lets;
StructuredBuffer<uint> file_option;
RWStructuredBuffer<uint4> marks;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> detail;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * GR_WORDS + word];
}

uint kind_of(uint token)
{
    return token < gCheck.token_count ? token_kind(tokens_out, token) : 0u;
}

void fail(uint token, uint code, uint a)
{
    generator_error(status, detail, tokens_out, gCheck.explain_key, token, code, a);
}

// Whether token `name` has the text of a parameter of generator `gen`.
bool names_param(uint gen, uint name)
{
    uint first = scan2[gen].x;
    uint count = min(scan2[rec(gen, GR_OWNER)].x - first, MAX_LIST);
    for (uint i = 0u; i < count; i += 1u)
    {
        if (same_token_text(tokens_out, in_bytes, params[first + i], name))
            return true;
    }
    return false;
}

bool assigns(uint kind)
{
    return kind == TK_ASSIGN || (kind >= TK_PLUS_ASSIGN && kind <= TK_PIPE_ASSIGN) || kind == TK_INC || kind == TK_DEC;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gCheck.token_count)
        return;
    uint role = rec(token, GR_ROLE);
    uint kind = token_kind(tokens_out, token);
    GenPlace place = gen_place(records, scan_a, scan1, gens, token);
    bool statement = place.inside && place.eligible;
    uint slots = 0u;
    uint pairs = 0u;
    uint pieces = 0u;

    if (role == GROLE_GEN)
    {
        uint flags = rec(token, GR_KIND);
        if (file_option[token_file_id[token]] == 0u)
            fail(token, GE_IMPORT, token);
        if ((flags & (GF_GENERIC | GF_WHERE)) != 0u)
            fail(token + 2u, GE_SIGNATURE, token);
        if ((flags & GF_NO_TYPE) != 0u)
            fail(rec(token, GR_OWNER) + 1u, GE_NO_TYPE, token);
    }
    if (kind == TK_YIELD)
    {
        if (!place.inside)
            fail(token, GE_OUTSIDE, token);
        else if (!place.eligible || role != GROLE_YIELD)
            fail(token, GE_PLACE, token);
        else
        {
            slots = scan2[token].z;
            pieces = YIELD_PIECES + 2u * slots;
        }
    }
    if (role == GROLE_YIELD_END && statement)
        pieces = YIELD_END_PIECES;
    if (kind == TK_RETURN && place.inside)
    {
        if (!place.eligible)
            fail(token, GE_PLACE, token);
        else if (kind_of(token + 1u) != TK_SEMICOLON)
            fail(token + 1u, GE_RETURN_VALUE, token);
        else
            pieces = RETURN_PIECES;
    }
    if (role == GROLE_LET && statement)
    {
        uint name = token + 1u;
        if (rec(token, GR_END) == 0u)
            fail(token + 2u, GE_LET_TYPE, token);
        bool twice = names_param(place.gen, name);
        uint first = scan2[place.open].y;
        uint earlier = min(scan2[token].y - 1u - first, MAX_LIST);
        for (uint i = 0u; i < earlier && !twice; i += 1u)
            twice = same_token_text(tokens_out, in_bytes, lets[first + i] + 1u, name);
        if (twice)
            fail(name, GE_LET_TWICE, name);
        pairs = scan1[rec(token, GR_CLOSE)].y - scan1[token].y;
    }
    if ((kind == TK_BREAK || kind == TK_CONTINUE) && scan1[token].z != 0u && scan1[token].z == scan2[token].w)
        fail(token, GE_LOOP_EXIT, token);
    if (kind == TK_IDENT && place.inside && token > 0u && assigns(kind_of(token + 1u)))
    {
        uint before = token_kind(tokens_out, token - 1u);
        if (before != TK_DOT && before != TK_LET && names_param(place.gen, token))
            fail(token, GE_PARAM_ASSIGN, token);
    }
    marks[token] = uint4(slots, pairs, pieces, 0u);
}
