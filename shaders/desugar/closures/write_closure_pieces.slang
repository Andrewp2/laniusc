// One lane writes the site and appendix of its closure. The compact scan
// gives their offsets, with sites preceding appendices within each file.
import shared.buffers.gpu_index;
import shared.syntax.generated_token_ids;
import desugar.tokens.desugaring_layout;
import closure_layout;

struct PieceParams
{
    uint token_count;
    uint closure_count;
    uint reserved1;
    uint reserved0;
};

ConstantBuffer<PieceParams> gPieces;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> source_file_start;
// Per token: the depth after it (x) and the closures that start through it (y).
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<uint4> count_scan;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> captures;
RWStructuredBuffer<uint4> pieces;
RWStructuredBuffer<uint> piece_owner;

static const uint SITE_PIECES = SITE_FIXED;

uint rec(uint k, uint word)
{
    return records[k * REC_WORDS + word];
}

uint closures_before(uint token)
{
    return token > 0u ? depth_scan[token - 1u].y : 0u;
}

// The first token of file `file` or a later one.
uint first_of(uint file)
{
    uint lo = 0u;
    uint hi = gPieces.token_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (token_file_id[mid] < file)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

uint4 constant(uint id, uint anchor)
{
    return uint4(1u, PIECE_CONST, id, anchor);
}

uint4 tokens(uint first, uint count)
{
    return uint4(count, PIECE_RANGE, first, first);
}

uint4 span(uint first, uint last)
{
    return tokens(first, last + 1u - first);
}

uint4 nothing(uint anchor)
{
    return uint4(0u, PIECE_RANGE, 0u, anchor);
}

// Piece `r` of the site of closure `k`.
uint4 site_piece(uint k, uint r, uint4 id)
{
    uint start = rec(k, REC_START);
    uint cap_first = rec(k, REC_CAP_FIRST);
    uint cap_count = rec(k, REC_CAP_COUNT);
    if (r == 0u)
        return constant(C_NAME, start);
    if (r == 1u)
        return id;
    if (r == 2u)
        return constant(C_LBRACE, start);
    if (r < 3u + cap_count * SITE_PER_CAPTURE)
    {
        uint at = r - 3u;
        uint name = captures[cap_first + at / SITE_PER_CAPTURE].y;
        uint part = at % SITE_PER_CAPTURE;
        if (part == 0u || part == 2u)
            return tokens(name, 1u);
        return constant(part == 1u ? C_COLON : C_COMMA, start);
    }
    return constant((rec(k, REC_FLAGS) & FLAG_MOVE) != 0u ? C_SITE_END_OWNED : C_SITE_END, start);
}

// Piece `r` of the appendix of closure `k`.
uint4 appendix_piece(uint k, uint r, uint4 id)
{
    uint start = rec(k, REC_START);
    uint cap_first = rec(k, REC_CAP_FIRST);
    uint cap_count = rec(k, REC_CAP_COUNT);
    uint flags = rec(k, REC_FLAGS);
    bool has_param = (flags & FLAG_NO_PARAM) == 0u;
    bool has_rtype = (flags & FLAG_RTYPE) != 0u;
    bool braced = (flags & FLAG_BRACED) != 0u;
    // A block body without a result type returns nothing.
    bool unit = braced && !has_rtype;
    uint4 result = has_rtype ? span(rec(k, REC_RTYPE_FIRST), rec(k, REC_RTYPE_LAST)) : constant(C_R, start);
    uint4 param_type = has_param ? span(rec(k, REC_PTYPE_FIRST), rec(k, REC_PTYPE_LAST)) : nothing(start);

    if (r == 0u)
        return constant(C_STRUCT, start);
    if (r == 1u)
        return id;
    if (r == 2u)
        return constant(C_LBRACE, start);
    r -= 3u;
    if (r < cap_count * 4u)
    {
        uint4 capture = captures[cap_first + r / 4u];
        uint part = r % 4u;
        if (part == 0u)
            return tokens(capture.y, 1u);
        if (part == 1u)
            return constant(C_COLON, start);
        if (part == 2u)
            return span(capture.z, capture.w);
        return constant(C_COMMA, start);
    }
    r -= cap_count * 4u;
    if (r < 19u)
    {
        if (r == 0u)
            return constant(C_IMPL, start);
        if (r == 1u || r == 3u || r == 11u)
            return id;
        if (r == 2u)
            return constant(C_BORROW, start);
        if (r == 4u)
            return constant(C_TRAIT_IMPL, start);
        if (r == 5u)
            return has_rtype || unit ? nothing(start) : constant(C_GENERIC_R, start);
        if (r == 6u)
            return constant(unit ? (has_param ? C_CONSUMER : C_RUNNABLE) : (has_param ? C_MAPPER : C_PRODUCER), start);
        if (r == 7u || r == 15u)
            return param_type;
        if (r == 8u)
            return has_param && !unit ? constant(C_COMMA, start) : nothing(start);
        if (r == 9u || r == 17u)
            return unit ? nothing(start) : result;
        if (r == 10u)
            return constant(unit && !has_param ? C_FOR_PLAIN : C_FOR, start);
        if (r == 12u)
            return constant(unit ? (has_param ? C_ACCEPT : C_RUN) : (has_param ? C_APPLY : C_PRODUCE), start);
        if (r == 13u)
            return has_param ? tokens(rec(k, REC_PARAM), 1u) : nothing(start);
        if (r == 14u)
            return has_param ? constant(C_COLON, start) : nothing(start);
        if (r == 16u)
            return constant(unit ? C_RPAREN : C_RET, start);
        return constant(C_LBRACE, start);
    }
    r -= 19u;
    if (r < cap_count * 7u)
    {
        uint4 capture = captures[cap_first + r / 7u];
        uint part = r % 7u;
        if (part == 0u)
            return constant(C_LET, start);
        if (part == 1u || part == 5u)
            return tokens(capture.y, 1u);
        if (part == 2u)
            return constant(C_COLON, start);
        if (part == 3u)
            return span(capture.z, capture.w);
        if (part == 4u)
            return constant(C_SELF, start);
        return constant(C_SEMI, start);
    }
    r -= cap_count * 7u;
    if (r == 0u)
        return braced ? nothing(start) : constant(C_RETURN, start);
    if (r == 1u)
        return span(rec(k, REC_BODY_FIRST), rec(k, REC_BODY_LAST));
    if (r == 2u)
        return constant(braced ? C_END_BLOCK : C_END_EXPR, start);
    // The entry function and the `Stored` impl. Only a `move` closure whose
    // result is known from its text gets them: the entry names the
    // closure's types, and an expression body does not state its result.
    uint e = r - 3u;
    if ((flags & FLAG_MOVE) == 0u || !(has_rtype || unit))
        return nothing(start);
    if (e == 0u)
        return constant(C_ENTRY_FN, start);
    if (e == 1u || e == 4u || e == 10u || e == 12u)
        return id;
    if (e == 2u)
        return constant(C_ENTRY_SIG, start);
    if (e == 3u)
        return constant(unit ? (has_param ? C_ENTER_CONSUMER : C_ENTER_RUNNABLE)
                             : (has_param ? C_ENTER_MAPPER : C_ENTER_PRODUCER), start);
    if (e == 5u)
        return has_param ? constant(C_COMMA, start) : nothing(start);
    if (e == 6u)
        return param_type;
    if (e == 7u)
        return has_rtype ? constant(C_COMMA, start) : nothing(start);
    if (e == 8u)
        return has_rtype ? result : nothing(start);
    if (e == 9u)
        return constant(C_ENTRY_END, start);
    if (e == 11u)
        return constant(C_STORED_FN, start);
    return constant(C_STORED_END, start);
}

// The ten digits that name closure `k`: the byte of its first token in its
// file.
uint4 closure_id(uint k, uint file)
{
    uint start = rec(k, REC_START);
    return uint4(1u, PIECE_ID, tokens_out[start].start - source_file_start[file], start);
}

uint2 pieces_before(uint closure)
{
    return closure == 0u ? uint2(0u) : count_scan[closure - 1u].xy;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint k = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (k >= gPieces.closure_count)
        return;
    uint file = rec(k, REC_FILE);
    uint end = first_of(file + 1u);
    uint first_closure = closures_before(first_of(file));
    uint end_closure = closures_before(end);
    uint2 first = pieces_before(first_closure);
    uint2 before = pieces_before(k);
    uint2 through = count_scan[k].xy;
    uint site_base = before.x + first.y;
    uint appendix_base = pieces_before(end_closure).x + before.y;
    uint4 id = closure_id(k, file);
    for (uint r = 0u; r < through.x - before.x; r += 1u)
    {
        pieces[site_base + r] = site_piece(k, r, id);
        piece_owner[site_base + r] = rec(k, REC_START);
    }
    for (uint r = 0u; r < through.y - before.y; r += 1u)
    {
        pieces[appendix_base + r] = appendix_piece(k, r, id);
        piece_owner[appendix_base + r] = end;
    }
}
