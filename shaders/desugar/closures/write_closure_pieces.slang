// The pieces of the closure round (desugaring_layout.slang). Every token emits
// its pieces in stream order:
//
//   the `|` that starts a closure: its site, a struct literal, owned by the
//     closure's first token, and every token of the closure is dropped;
//   the last token of a file with a closure: the appendix of each of the
//     file's closures, owned by the token after it.
//
// Mode 0 runs per token: it counts the pieces of each token, drops the
// tokens of the closures, compacts the captures into one list in token
// order and gives each closure its range of that list. Mode 1 runs per
// piece and writes it; `count_scan.x` is the inclusive prefix sum of the
// counts, so the token that emits a piece is the first whose sum passes it.
import shared.buffers.gpu_index;
import shared.syntax.generated_token_ids;
import desugar.tokens.desugaring_layout;
import closure_layout;

struct PieceParams
{
    uint token_count;
    uint mode;
    uint piece_count;
    uint reserved0;
};

ConstantBuffer<PieceParams> gPieces;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> source_file_start;
// Per token: the depth after it (x) and the closures that start through it (y).
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<uint4> capture_marks;
StructuredBuffer<uint4> capture_scan;
StructuredBuffer<uint4> count_scan;
RWStructuredBuffer<uint> records;
RWStructuredBuffer<uint4> captures;
RWStructuredBuffer<uint4> counts;
RWStructuredBuffer<uint4> pieces;
RWStructuredBuffer<uint> piece_owner;
RWStructuredBuffer<uint> drop;

static const uint SITE_PIECES = SITE_FIXED;

uint rec(uint k, uint word)
{
    return records[k * REC_WORDS + word];
}

uint closures_before(uint token)
{
    return token > 0u ? depth_scan[token - 1u].y : 0u;
}

uint captures_before(uint token)
{
    return token > 0u ? capture_scan[token - 1u].x : 0u;
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

struct FileSpan
{
    uint first;
    uint last;
    uint closures;
    uint captures;
};

FileSpan file_span(uint file)
{
    FileSpan span;
    span.first = first_of(file);
    span.last = first_of(file + 1u) - 1u;
    span.closures = depth_scan[span.last].y - closures_before(span.first);
    span.captures = capture_scan[span.last].x - captures_before(span.first);
    return span;
}

bool last_in_file(uint t, uint file)
{
    return t + 1u == gPieces.token_count || token_file_id[t + 1u] != file;
}

bool starts_closure(uint t)
{
    return depth_scan[t].y != closures_before(t);
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

void count_token(uint t)
{
    uint file = token_file_id[t];
    uint4 mark = capture_marks[t];
    if (mark.x == 1u)
        captures[capture_scan[t].x - 1u] = uint4(mark.w, t, mark.y, mark.z);

    uint n = 0u;
    if (starts_closure(t))
    {
        uint k = depth_scan[t].y - 1u;
        uint body_first = rec(k, REC_BODY_FIRST);
        uint body_last = rec(k, REC_BODY_LAST);
        uint first = 0u;
        uint count = 0u;
        if (body_last >= body_first)
        {
            first = captures_before(body_first);
            count = capture_scan[body_last].x - first;
        }
        records[k * REC_WORDS + REC_CAP_FIRST] = first;
        records[k * REC_WORDS + REC_CAP_COUNT] = count;
        n += SITE_PIECES + SITE_PER_CAPTURE * count;
    }
    if (last_in_file(t, file))
    {
        FileSpan span = file_span(file);
        if (span.closures > 0u)
            n += APPENDIX_FIXED * span.closures + APPENDIX_PER_CAPTURE * span.captures;
    }
    counts[t] = uint4(n, 0u, 0u, 0u);

    // The closure that starts last at or before this token.
    uint lo = 0u;
    uint hi = depth_scan[gPieces.token_count - 1u].y;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (rec(mid, REC_START) <= t)
            lo = mid + 1u;
        else
            hi = mid;
    }
    bool inside = false;
    if (lo > 0u)
    {
        uint body_first = rec(lo - 1u, REC_BODY_FIRST);
        uint body_last = rec(lo - 1u, REC_BODY_LAST);
        inside = body_last >= body_first && t <= body_last;
    }
    drop[t] = inside ? 1u : 0u;
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

void write_piece(uint q)
{
    uint lo = 0u;
    uint hi = gPieces.token_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (count_scan[mid].x <= q)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint t = lo;
    if (t >= gPieces.token_count)
        return;
    uint r = q - (count_scan[t].x - counts[t].x);
    uint file = token_file_id[t];

    if (starts_closure(t))
    {
        uint k = depth_scan[t].y - 1u;
        uint site = SITE_PIECES + SITE_PER_CAPTURE * rec(k, REC_CAP_COUNT);
        if (r < site)
        {
            pieces[q] = site_piece(k, r, closure_id(k, file));
            piece_owner[q] = rec(k, REC_START);
            return;
        }
        r -= site;
    }

    // The appendix of the file's closures, after its last token.
    FileSpan span = file_span(file);
    uint k0 = closures_before(span.first);
    uint cap_base = rec(k0, REC_CAP_FIRST);
    uint low = 0u;
    uint high = span.closures;
    for (uint guard = 0u; guard < 32u && low < high; guard += 1u)
    {
        uint mid = low + ((high - low) >> 1u);
        uint before = mid * APPENDIX_FIXED + (rec(k0 + mid, REC_CAP_FIRST) - cap_base) * APPENDIX_PER_CAPTURE;
        if (before <= r)
            low = mid + 1u;
        else
            high = mid;
    }
    uint m = low - 1u;
    uint k = k0 + m;
    r -= m * APPENDIX_FIXED + (rec(k, REC_CAP_FIRST) - cap_base) * APPENDIX_PER_CAPTURE;
    pieces[q] = appendix_piece(k, r, closure_id(k, file));
    piece_owner[q] = t + 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint index = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (gPieces.mode == 0u)
    {
        if (index < gPieces.token_count)
            count_token(index);
        return;
    }
    if (index < gPieces.piece_count)
        write_piece(index);
}
