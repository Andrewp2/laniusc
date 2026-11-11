// Per output piece: its length and where its bytes come from. The rewritten
// pack is the pieces in order. A file is
//
//   text before the import, the import,
//   per closure: the text before it and its site,
//   the text after the last closure,
//   per closure: its appendix.
//
// The owner of a piece follows from the closure and capture counts alone, so
// every piece is computed independently.
import gpu_index;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

struct LayoutParams
{
    uint file_count;
    uint closure_count;
    uint capture_count;
    uint piece_count;
    uint byte_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<LayoutParams> gLayout;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> source_file_len;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> captures;
StructuredBuffer<uint4> file_info;
StructuredBuffer<uint> const_index;
RWStructuredBuffer<uint4> pieces;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint SITE_PIECES = 1u + SITE_FIXED;

uint file_base(uint file)
{
    uint4 info = file_info[file];
    return file * PIECES_PER_FILE + info.y * PIECES_PER_CLOSURE + info.z * PIECES_PER_CAPTURE;
}

uint token_start(uint token)
{
    return tokens_out[token].start;
}

uint token_end(uint token)
{
    return tokens_out[token].start + tokens_out[token].len;
}

uint4 copy_bytes(uint first, uint end, uint owner)
{
    return uint4(end > first ? end - first : 0u, PIECE_COPY, first, owner);
}

uint4 copy_token(uint token, uint owner)
{
    return copy_bytes(token_start(token), token_end(token), owner);
}

uint4 copy_span(uint first, uint last, uint owner)
{
    return copy_bytes(token_start(first), token_end(last), owner);
}

uint4 constant(uint id, uint owner)
{
    return uint4(const_index[id * 2u + 1u], PIECE_CONST, id, owner);
}

uint4 nothing(uint owner)
{
    return uint4(0u, PIECE_COPY, 0u, owner);
}

// The closure of a file whose pieces contain `local`. A closure has `fixed`
// pieces plus `per_capture` for each capture.
uint owning_closure(uint local, uint first_closure, uint closure_count, uint first_capture, uint fixed,
                    uint per_capture)
{
    uint lo = 0u;
    uint hi = closure_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint captures_before = records[(first_closure + mid) * REC_WORDS + REC_CAP_FIRST] - first_capture;
        if (mid * fixed + captures_before * per_capture <= local)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint q = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (q >= gLayout.piece_count)
        return;

    // The last file whose pieces start at or before this one.
    uint lo = 0u;
    uint hi = gLayout.file_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (file_base(mid) <= q)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint file = lo - 1u;
    uint4 info = file_info[file];
    uint4 next_info = file_info[file + 1u];
    uint first_closure = info.y;
    uint first_capture = info.z;
    uint closure_count = next_info.y - first_closure;
    uint capture_count = next_info.z - first_capture;
    uint file_start = source_file_start[file];
    uint file_end = file_start + source_file_len[file];
    uint import_at = info.w;
    uint local = q - file_base(file);

    if (local == 0u)
    {
        pieces[q] = copy_bytes(file_start, import_at, CL_INVALID);
        return;
    }
    if (local == 1u)
    {
        pieces[q] = closure_count > 0u ? constant(C_IMPORT, CL_INVALID) : nothing(CL_INVALID);
        return;
    }
    local -= 2u;

    uint site_total = closure_count * SITE_PIECES + capture_count * SITE_PER_CAPTURE;
    if (local == site_total)
    {
        uint from = import_at;
        if (closure_count > 0u)
            from = token_end(records[(first_closure + closure_count - 1u) * REC_WORDS + REC_BODY_LAST]);
        pieces[q] = copy_bytes(from, file_end, CL_INVALID);
        return;
    }

    bool site = local < site_total;
    if (!site)
        local -= site_total + 1u;
    uint fixed = site ? SITE_PIECES : APPENDIX_FIXED;
    uint per_capture = site ? SITE_PER_CAPTURE : APPENDIX_PER_CAPTURE;
    uint in_file = owning_closure(local, first_closure, closure_count, first_capture, fixed, per_capture);
    uint k = first_closure + in_file;
    uint row = k * REC_WORDS;
    uint cap_first = records[row + REC_CAP_FIRST];
    uint cap_count = records[row + REC_CAP_COUNT];
    uint r = local - (in_file * fixed + (cap_first - first_capture) * per_capture);
    uint start = records[row + REC_START];
    uint flags = records[row + REC_FLAGS];
    uint4 id = uint4(ID_DIGITS, PIECE_ID, token_start(start) - file_start, k);

    if (site)
    {
        if (r == 0u)
        {
            uint from = import_at;
            if (in_file > 0u)
                from = token_end(records[(k - 1u) * REC_WORDS + REC_BODY_LAST]);
            pieces[q] = copy_bytes(from, token_start(start), CL_INVALID);
        }
        else if (r == 1u)
        {
            pieces[q] = constant(C_NAME, k);
        }
        else if (r == 2u)
        {
            pieces[q] = id;
        }
        else if (r == 3u)
        {
            pieces[q] = constant(C_LBRACE, k);
        }
        else if (r < 4u + cap_count * SITE_PER_CAPTURE)
        {
            uint at = r - 4u;
            uint name = captures[cap_first + at / SITE_PER_CAPTURE].y;
            uint part = at % SITE_PER_CAPTURE;
            if (part == 0u || part == 2u)
                pieces[q] = copy_token(name, k);
            else
                pieces[q] = constant(part == 1u ? C_COLON : C_COMMA, k);
        }
        else
        {
            pieces[q] = constant((flags & FLAG_MOVE) != 0u ? C_SITE_END_OWNED : C_SITE_END, k);
        }
        return;
    }

    bool has_param = (flags & FLAG_NO_PARAM) == 0u;
    bool has_rtype = (flags & FLAG_RTYPE) != 0u;
    bool braced = (flags & FLAG_BRACED) != 0u;
    uint param = records[row + REC_PARAM];
    uint ptype_first = records[row + REC_PTYPE_FIRST];
    uint ptype_last = records[row + REC_PTYPE_LAST];
    uint rtype_first = records[row + REC_RTYPE_FIRST];
    uint rtype_last = records[row + REC_RTYPE_LAST];
    uint4 result = has_rtype ? copy_span(rtype_first, rtype_last, k) : constant(C_R, k);
    uint4 param_type = has_param ? copy_span(ptype_first, ptype_last, k) : nothing(k);

    if (r == 0u)
    {
        pieces[q] = constant(C_STRUCT, k);
        return;
    }
    if (r == 1u)
    {
        pieces[q] = id;
        return;
    }
    if (r == 2u)
    {
        pieces[q] = constant(C_LBRACE, k);
        return;
    }
    r -= 3u;
    if (r < cap_count * 4u)
    {
        uint4 capture = captures[cap_first + r / 4u];
        uint part = r % 4u;
        if (part == 0u)
            pieces[q] = copy_token(capture.y, k);
        else if (part == 1u)
            pieces[q] = constant(C_COLON, k);
        else if (part == 2u)
            pieces[q] = copy_span(capture.z, capture.w, k);
        else
            pieces[q] = constant(C_COMMA, k);
        return;
    }
    r -= cap_count * 4u;
    if (r < 19u)
    {
        uint4 piece = nothing(k);
        if (r == 0u)
            piece = constant(C_IMPL, k);
        else if (r == 1u || r == 3u || r == 11u)
            piece = id;
        else if (r == 2u)
            piece = constant(C_BORROW, k);
        else if (r == 4u)
            piece = constant(C_TRAIT_IMPL, k);
        else if (r == 5u)
            piece = has_rtype ? nothing(k) : constant(C_GENERIC_R, k);
        else if (r == 6u)
            piece = constant(has_param ? C_MAPPER : C_PRODUCER, k);
        else if (r == 7u || r == 15u)
            piece = param_type;
        else if (r == 8u)
            piece = has_param ? constant(C_COMMA, k) : nothing(k);
        else if (r == 9u || r == 17u)
            piece = result;
        else if (r == 10u)
            piece = constant(C_FOR, k);
        else if (r == 12u)
            piece = constant(has_param ? C_APPLY : C_PRODUCE, k);
        else if (r == 13u)
            piece = has_param ? copy_token(param, k) : nothing(k);
        else if (r == 14u)
            piece = has_param ? constant(C_COLON, k) : nothing(k);
        else if (r == 16u)
            piece = constant(C_RET, k);
        else
            piece = constant(C_LBRACE, k);
        pieces[q] = piece;
        return;
    }
    r -= 19u;
    if (r < cap_count * 7u)
    {
        uint4 capture = captures[cap_first + r / 7u];
        uint part = r % 7u;
        if (part == 0u)
            pieces[q] = constant(C_LET, k);
        else if (part == 1u || part == 5u)
            pieces[q] = copy_token(capture.y, k);
        else if (part == 2u)
            pieces[q] = constant(C_COLON, k);
        else if (part == 3u)
            pieces[q] = copy_span(capture.z, capture.w, k);
        else if (part == 4u)
            pieces[q] = constant(C_SELF, k);
        else
            pieces[q] = constant(C_SEMI, k);
        return;
    }
    r -= cap_count * 7u;
    if (r == 0u)
        pieces[q] = braced ? nothing(k) : constant(C_RETURN, k);
    else if (r == 1u)
        pieces[q] = copy_span(records[row + REC_BODY_FIRST], records[row + REC_BODY_LAST], k);
    else
        pieces[q] = constant(braced ? C_END_BLOCK : C_END_EXPR, k);
}
