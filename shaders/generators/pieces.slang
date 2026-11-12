// The pieces of generated text. Three kinds of token own pieces: `gen` owns
// the text before its generator, the machine's head and the `Start` state;
// a `yield` owns its state; the `}` of the body owns the `Done` state, the
// constructor, the impl and, for a file's last generator, the text after it.
//
// The kernel runs twice with the same control flow. The first run has one
// thread per token and counts the token's pieces. The second has one thread
// per piece: it finds the owner from the prefix sums of those counts, walks
// the owner's sections to the piece and writes it.
//
// A section that copies statements of the body is a run of tokens. In it a
// `yield`, the `;` after it and a `return` are replaced, so the run's pieces
// are the replacements with the copied text between them. The prefix sums
// of the replacement sizes give a run's piece count and the token of a
// piece without a walk over the run.
import gpu_index;
import generated_token_ids;
import generator_common;

struct PieceParams
{
    uint token_count;
    uint write;
    uint piece_count;
    uint gen_count;
};

ConstantBuffer<PieceParams> gPieces;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> source_file_len;
StructuredBuffer<uint> records;
// Inclusive prefix sums: generators, yields, loop depth, statement depth.
StructuredBuffer<uint4> scan1;
// Inclusive prefix sums: parameters, locals, locals in scope, depth in the
// loops that hold a `yield`.
StructuredBuffer<uint4> scan2;
// Inclusive prefix sums: slots of yields, pairs of locals, pieces that
// replace tokens.
StructuredBuffer<uint4> scan3;
StructuredBuffer<uint> gens;
StructuredBuffer<uint> params;
// The locals in scope at each yield, outermost first.
StructuredBuffer<uint> scope;
StructuredBuffer<uint> const_index;
// Inclusive prefix sums of the piece counts, read by the writing run.
StructuredBuffer<uint4> count_scan;
RWStructuredBuffer<uint4> counts;
RWStructuredBuffer<uint4> pieces;
// Per piece: the file, start and length of its anchor token.
RWStructuredBuffer<uint4> piece_sources;

static const uint DISPATCH_X_STRIDE = 16776960u;

struct Cursor
{
    // The pieces passed so far, and the one to write.
    uint at;
    uint target;
    uint4 row;
    // The target is piece `range_index` of the copy of tokens
    // `[range_first, range_end)`.
    bool in_range;
    uint range_first;
    uint range_end;
    uint range_index;
};

struct Gen
{
    uint head;
    uint name;
    uint open;
    uint close;
    uint params_close;
    uint flags;
    uint first_param;
    uint param_count;
};

uint rec(uint token, uint word)
{
    return records[token * GR_WORDS + word];
}

uint start_of(uint token)
{
    return token_start(tokens_out, token);
}

uint end_of(uint token)
{
    return token_end(tokens_out, token);
}

uint replaced_through(uint token)
{
    return scan3[token].z;
}

bool within(Cursor cur, uint count)
{
    return cur.target != GN_NONE && cur.target >= cur.at && cur.target - cur.at < count;
}

void put(inout Cursor cur, uint len, uint kind, uint value, uint anchor)
{
    if (cur.at == cur.target)
        cur.row = uint4(len, kind, value, anchor);
    cur.at += 1u;
}

void text(inout Cursor cur, uint id, uint anchor)
{
    put(cur, const_index[id * 2u + 1u], PIECE_CONST, id, anchor);
}

void bytes(inout Cursor cur, uint from, uint to, uint anchor)
{
    put(cur, to > from ? to - from : 0u, PIECE_COPY, from, anchor);
}

void token(inout Cursor cur, uint t)
{
    bytes(cur, start_of(t), end_of(t), t);
}

// The source text of tokens `[first, end)`.
void span(inout Cursor cur, uint first, uint end)
{
    bytes(cur, start_of(first), end > first ? end_of(end - 1u) : start_of(first), first);
}

uint digits(uint value)
{
    uint count = 1u;
    for (uint rest = value; rest >= 10u; rest /= 10u)
        count += 1u;
    return count;
}

void number(inout Cursor cur, uint value, uint anchor)
{
    put(cur, digits(value), PIECE_NUMBER, value, anchor);
}

// The machine's name: the CamelCase form of the function's. The writing
// run fills in the length.
void camel(inout Cursor cur, uint name)
{
    put(cur, 0u, PIECE_CAMEL, 0u, name);
}

Gen gen_at(uint head)
{
    Gen g;
    g.head = head;
    g.name = head + 2u;
    g.open = rec(head, GR_OPEN);
    g.close = rec(head, GR_END) - 1u;
    g.params_close = rec(head, GR_OWNER);
    g.flags = rec(head, GR_KIND);
    g.first_param = scan2[head].x;
    g.param_count = min(scan2[g.params_close].x - g.first_param, MAX_LIST);
    return g;
}

Gen gen_of(uint token)
{
    return gen_at(gens[scan1[token].x - 1u]);
}

void public_word(inout Cursor cur, Gen g)
{
    text(cur, (g.flags & GF_PUBLIC) != 0u ? GC_PUB : GC_EMPTY, g.name);
}

// The yielded type.
void output_type(inout Cursor cur, Gen g)
{
    span(cur, g.params_close + 2u, g.open);
}

// The copy of tokens `[first, end)` of a body.
void range(inout Cursor cur, uint first, uint end)
{
    uint count = 1u;
    if (end > first)
        count += replaced_through(end - 1u) - replaced_through(first - 1u);
    if (within(cur, count))
    {
        cur.in_range = true;
        cur.range_first = first;
        cur.range_end = end;
        cur.range_index = cur.target - cur.at;
    }
    cur.at += count;
}

// `    name: Type,` per parameter: the machine's fields.
void fields(inout Cursor cur, Gen g)
{
    uint base = cur.at;
    uint count = g.param_count * 3u;
    if (within(cur, count))
    {
        uint i = (cur.target - base) / 3u;
        uint p = params[g.first_param + i];
        cur.at = base + i * 3u;
        text(cur, GC_INDENT, p);
        span(cur, p, rec(p, GR_END));
        text(cur, GC_FIELD_END, p);
    }
    cur.at = base + count;
}

// `let name: Type = self.name; ` per parameter, at the start of an arm.
void param_lets(inout Cursor cur, Gen g)
{
    uint base = cur.at;
    uint count = g.param_count * 5u;
    if (within(cur, count))
    {
        uint i = (cur.target - base) / 5u;
        uint p = params[g.first_param + i];
        cur.at = base + i * 5u;
        text(cur, GC_LET, p);
        span(cur, p, rec(p, GR_END));
        text(cur, GC_FROM_SELF, p);
        token(cur, p);
        text(cur, GC_STATEMENT_END, p);
    }
    cur.at = base + count;
}

// `name: Type, ...` with `typed`, otherwise `name, ...`.
void param_list(inout Cursor cur, Gen g, bool typed)
{
    uint base = cur.at;
    uint count = g.param_count * 2u;
    if (within(cur, count))
    {
        uint i = (cur.target - base) / 2u;
        uint p = params[g.first_param + i];
        cur.at = base + i * 2u;
        text(cur, i == 0u ? GC_EMPTY : GC_COMMA, p);
        span(cur, p, typed ? rec(p, GR_END) : p + 1u);
    }
    cur.at = base + count;
}

// `(__lanius_gen_name: Type, ...`: the data of a yield's state.
void state_data(inout Cursor cur, uint first_slot, uint slots)
{
    uint base = cur.at;
    uint count = slots * 2u;
    if (within(cur, count))
    {
        uint r = (cur.target - base) / 2u;
        uint local = scope[first_slot + r];
        cur.at = base + r * 2u;
        text(cur, r == 0u ? GC_DATA_FIRST : GC_DATA_NEXT, local + 1u);
        span(cur, local + 1u, rec(local, GR_END));
    }
    cur.at = base + count;
}

// The start of a yield's arm: each local in scope is declared from the
// state's data, and a block opens for each block around the yield. Local
// `r` follows the blocks of its level, so its pieces start at
// `5 * r + level`.
void prologue(inout Cursor cur, Gen g, uint y, uint first_slot, uint slots, uint depth)
{
    uint base = cur.at;
    uint count = slots * 5u + depth;
    if (within(cur, count))
    {
        uint q = cur.target - base;
        uint lo = 0u;
        uint hi = slots;
        for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
        {
            uint mid = lo + ((hi - lo) >> 1u);
            uint local = scope[first_slot + mid];
            if (mid * 5u + (scan1[local].w - scan1[g.open].w) <= q)
                lo = mid + 1u;
            else
                hi = mid;
        }
        bool declared = false;
        if (lo > 0u)
        {
            uint r = lo - 1u;
            uint local = scope[first_slot + r];
            uint start = r * 5u + (scan1[local].w - scan1[g.open].w);
            if (q - start < 5u)
            {
                uint name = local + 1u;
                cur.at = base + start;
                text(cur, GC_LET, name);
                span(cur, name, rec(local, GR_END));
                text(cur, GC_FROM_DATA, name);
                token(cur, name);
                text(cur, GC_STATEMENT_END, name);
                declared = true;
            }
        }
        if (!declared)
        {
            cur.at = cur.target;
            text(cur, GC_BLOCK_OPEN, y);
        }
    }
    cur.at = base + count;
}

// The text before the generator, the machine's head and its `Start` state.
void head(inout Cursor cur, Gen g)
{
    uint file = token_file_id[g.head];
    uint item = (g.flags & GF_PUBLIC) != 0u ? g.head - 1u : g.head;
    uint from = source_file_start[file];
    uint ordinal = scan1[g.head].x;
    if (ordinal >= 2u)
    {
        uint previous = gens[ordinal - 2u];
        if (token_file_id[previous] == file)
            from = end_of(rec(previous, GR_END) - 1u);
    }
    bytes(cur, from, start_of(item), item);

    public_word(cur, g);
    text(cur, GC_ENUM, g.name);
    camel(cur, g.name);
    text(cur, GC_RESUME_ENUM, g.name);
    public_word(cur, g);
    text(cur, GC_MACHINE, g.name);
    camel(cur, g.name);
    text(cur, GC_ON, g.name);
    camel(cur, g.name);
    text(cur, GC_RESUME_OUTPUT, g.name);
    output_type(cur, g);
    text(cur, GC_OUTPUT_END, g.name);
    fields(cur, g);
    text(cur, GC_START_STATE, g.name);
    camel(cur, g.name);
    text(cur, GC_ARM, g.name);
    param_lets(cur, g);
    range(cur, g.open + 1u, g.close);
    text(cur, GC_ARM_END, g.close);
}

// The state of `yield` `y`: its arm runs the rest of the yield's block,
// then the rest of each statement around it. A `while` around the yield
// runs again in full.
void state(inout Cursor cur, uint y)
{
    Gen g = gen_of(y);
    uint slots = scan2[y].z;
    uint first_slot = scan3[y].x - slots;
    uint depth = min(scan1[y].w - scan1[g.open].w, MAX_DEPTH);
    text(cur, GC_STATE_YIELD, y);
    number(cur, scan1[y].y - 1u - scan1[g.open].y, y);
    state_data(cur, first_slot, slots);
    text(cur, slots != 0u ? GC_DATA_CLOSE : GC_STATE_OPEN, y);
    camel(cur, g.name);
    text(cur, GC_ARM, y);
    param_lets(cur, g);
    prologue(cur, g, y, first_slot, slots, depth);
    uint close = rec(y, GR_CLOSE);
    uint after = rec(y, GR_NEXT);
    for (uint step = 0u; step <= depth; step += 1u)
    {
        range(cur, after, close);
        if (step == depth)
            break;
        text(cur, GC_BLOCK_CLOSE, close);
        uint open = rec(close, GR_OPEN);
        uint owner = rec(open, GR_OWNER);
        uint owner_end = rec(owner, GR_NEXT);
        if (rec(open, GR_KIND) == BK_WHILE)
            range(cur, owner, owner_end);
        after = owner_end;
        close = rec(owner, GR_CLOSE);
    }
    text(cur, GC_ARM_END, y);
}

// The `Done` state, the function that constructs the machine, the impl with
// `next`, and the text after the file's last generator.
void tail(inout Cursor cur, uint close)
{
    Gen g = gen_of(close);
    text(cur, GC_DONE_STATE, g.name);
    camel(cur, g.name);
    text(cur, GC_DONE_ARM, g.name);

    public_word(cur, g);
    text(cur, GC_FN, g.name);
    token(cur, g.name);
    text(cur, GC_LPAREN, g.name);
    param_list(cur, g, true);
    text(cur, GC_RETURNS, g.name);
    camel(cur, g.name);
    text(cur, GC_RETURN, g.name);
    put(cur, 0u, PIECE_CAMEL_SNAKE, 0u, g.name);
    text(cur, GC_START_CALL, g.name);
    param_list(cur, g, false);
    text(cur, GC_FN_END, g.name);

    public_word(cur, g);
    text(cur, GC_IMPL, g.name);
    camel(cur, g.name);
    text(cur, GC_IMPL_OPEN, g.name);
    public_word(cur, g);
    text(cur, GC_NEXT, g.name);
    output_type(cur, g);
    text(cur, GC_NEXT_BODY, g.name);
    camel(cur, g.name);
    text(cur, GC_NEXT_END, g.name);

    uint file = token_file_id[close];
    uint ordinal = scan1[close].x;
    bool last = ordinal >= gPieces.gen_count || token_file_id[gens[ordinal]] != file;
    uint end = end_of(close);
    bytes(cur, end, last ? source_file_start[file] + source_file_len[file] : end, close);
}

void sections(inout Cursor cur, uint owner)
{
    uint role = rec(owner, GR_ROLE);
    if (role == GROLE_GEN)
        head(cur, gen_at(owner));
    else if (role == GROLE_YIELD && owner > 0u && replaced_through(owner) != replaced_through(owner - 1u))
        state(cur, owner);
    else if (role == GROLE_CLOSE && rec(rec(owner, GR_OPEN), GR_KIND) == BK_BODY)
        tail(cur, owner);
}

// The first token of `[first, end)` whose replacements end after piece
// `want`, or `end`.
uint token_of_piece(uint first, uint end, uint want)
{
    uint lo = first;
    uint hi = end;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (replaced_through(mid) <= want)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

uint4 constant(uint id, uint anchor)
{
    return uint4(const_index[id * 2u + 1u], PIECE_CONST, id, anchor);
}

uint4 copy(uint from, uint to, uint anchor)
{
    return uint4(to > from ? to - from : 0u, PIECE_COPY, from, anchor);
}

// Piece `index` of the copy of tokens `[first, end)` of the body that opens
// at `body_open`.
uint4 range_piece(uint first, uint end, uint index, uint body_open)
{
    uint before = replaced_through(first - 1u);
    uint want = before + index;
    uint t = token_of_piece(first, end, want);
    uint prior = replaced_through(t - 1u);

    // The copied text before `t` starts after the replaced token before it.
    uint from = start_of(first);
    if (prior > before)
    {
        uint p = token_of_piece(first, t, prior - 1u);
        uint role = rec(p, GR_ROLE);
        from = role == GROLE_YIELD ? start_of(p + 1u) : (role == GROLE_YIELD_END ? start_of(p) : end_of(p));
    }
    if (t >= end)
        return copy(from, end_of(end - 1u), first);
    uint k = want - prior;
    if (k == 0u)
        return copy(from, start_of(t), t);
    uint role = rec(t, GR_ROLE);
    if (role == GROLE_YIELD_END)
        return constant(GC_RPAREN, rec(t, GR_OPEN));
    if (role != GROLE_YIELD)
        return constant(GC_GOTO_DONE, t);

    // `goto YieldK(a, b) with core::option::Some(`.
    uint slots = scan2[t].z;
    if (k == 1u)
        return constant(GC_GOTO_YIELD, t);
    if (k == 2u)
    {
        uint ordinal = scan1[t].y - 1u - scan1[body_open].y;
        return uint4(digits(ordinal), PIECE_NUMBER, ordinal, t);
    }
    if (k == 3u + 2u * slots)
        return constant(slots != 0u ? GC_SOME_AFTER_DATA : GC_SOME, t);
    uint r = (k - 3u) >> 1u;
    if (((k - 3u) & 1u) == 0u)
        return constant(r == 0u ? GC_LPAREN : GC_COMMA, t);
    uint name = scope[scan3[t].x - slots + r] + 1u;
    return copy(start_of(name), end_of(name), name);
}

Cursor cursor(uint target)
{
    Cursor cur;
    cur.at = 0u;
    cur.target = target;
    cur.row = uint4(0u, PIECE_COPY, 0u, 0u);
    cur.in_range = false;
    cur.range_first = 0u;
    cur.range_end = 0u;
    cur.range_index = 0u;
    return cur;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint index = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (gPieces.write == 0u)
    {
        if (index >= gPieces.token_count)
            return;
        Cursor counter = cursor(GN_NONE);
        sections(counter, index);
        counts[index] = uint4(counter.at, 0u, 0u, 0u);
        return;
    }
    if (index >= gPieces.piece_count)
        return;
    // The owner of this piece: the first token whose pieces end after it.
    uint lo = 0u;
    uint hi = gPieces.token_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (count_scan[mid].x <= index)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gPieces.token_count)
        return;
    uint owner = lo;
    Cursor cur = cursor(index - (owner > 0u ? count_scan[owner - 1u].x : 0u));
    sections(cur, owner);
    uint4 row = cur.row;
    if (cur.in_range)
        row = range_piece(cur.range_first, cur.range_end, cur.range_index, gen_of(owner).open);
    if (row.y == PIECE_CAMEL || row.y == PIECE_CAMEL_SNAKE)
        row.x = camel_text(in_bytes, start_of(row.w), token_len(tokens_out, row.w), row.y == PIECE_CAMEL_SNAKE, GN_NONE);
    pieces[index] = row;
    piece_sources[index] = uint4(token_file_id[row.w], start_of(row.w), token_len(tokens_out, row.w), 0u);
}
