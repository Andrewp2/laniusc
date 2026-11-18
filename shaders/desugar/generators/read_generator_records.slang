// Per token: the records of a generator, read from the token stream by the
// thread of its `gen` token (generator_layout.slang has the layout).
//
// The thread reads the header: the name, the parameters with their types,
// the yielded type and the body. Then it walks the statements of the body
// and of the blocks of its `while` and `if` statements, the places a
// `yield` may stand: each statement gets the first token of the next one and
// the `}` of its block, and a `let`, `yield` or `return` its role. Last it
// records the block of every loop in the body, so the loop depth counts the
// loops a `break` may leave.
//
// A generator whose header or brackets do not match is not recorded; the
// parser reports it.
import shared.buffers.gpu_index;
import shared.syntax.generated_token_ids;
import generator_layout;

struct ReadParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ReadParams> gRead;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
RWStructuredBuffer<uint> records;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint FAIL = 0xffffffffu;
// Bounds the loops of one generator. No generator of a program that fits
// the compiler's limits reaches them.
static const uint MAX_ITEM_TOKENS = 1u << 22u;

// The kind of token `t` when it lies in file `file`, otherwise FAIL.
uint kind_in(uint t, uint file)
{
    if (t >= gRead.token_count || token_file_id[t] != file)
        return FAIL;
    return token_kind(tokens_out, t);
}

void store(uint token, uint word, uint value)
{
    if (token < gRead.token_count)
        records[token * GR_WORDS + word] = value;
}

bool opens(uint kind)
{
    return kind == TK_LPAREN || kind == TK_LBRACKET || kind == TK_LBRACE;
}

bool closes(uint kind)
{
    return kind == TK_RPAREN || kind == TK_RBRACKET || kind == TK_RBRACE;
}

// The token after the bracket group that opens at `t`, or FAIL.
uint group_end(uint t, uint file)
{
    uint depth = 0u;
    for (uint at = t; at - t < MAX_ITEM_TOKENS; at += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == FAIL)
            return FAIL;
        if (opens(kind))
            depth += 1u;
        else if (closes(kind))
        {
            depth -= 1u;
            if (depth == 0u)
                return at + 1u;
        }
    }
    return FAIL;
}

// The first `{` outside brackets in `[t, limit)`, or FAIL.
uint first_brace(uint t, uint limit, uint file)
{
    uint depth = 0u;
    for (uint at = t; at < limit && at - t < MAX_ITEM_TOKENS; at += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == FAIL)
            return FAIL;
        if (kind == TK_LBRACE && depth == 0u)
            return at;
        if (opens(kind))
            depth += 1u;
        else if (closes(kind))
        {
            if (depth == 0u)
                return FAIL;
            depth -= 1u;
        }
    }
    return FAIL;
}

// The token after the `{ ... }` of the construct at `t`, or FAIL.
uint braced_end(uint t, uint limit, uint file)
{
    uint open = first_brace(t, limit, file);
    return open == FAIL ? FAIL : group_end(open, file);
}

// The token after a type that starts at `t`: the first `,`, `=` or `;`
// outside brackets, or the bracket that closes around the type. `<` and
// `>` count as brackets.
uint type_end(uint t, uint limit, uint file)
{
    uint depth = 0u;
    for (uint at = t; at < limit && at - t < MAX_ITEM_TOKENS; at += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == FAIL)
            return at;
        if (opens(kind) || kind == TK_LT)
            depth += 1u;
        else if (closes(kind) || kind == TK_GT || kind == TK_SHR)
        {
            uint step = kind == TK_SHR ? 2u : 1u;
            if (depth < step)
                return at;
            depth -= step;
        }
        else if (depth == 0u && (kind == TK_COMMA || kind == TK_ASSIGN || kind == TK_SEMICOLON))
            return at;
    }
    return limit;
}

// The token after the `if` chain at `t`: each arm's block and the `else`.
uint chain_end(uint t, uint close, uint file)
{
    uint at = t;
    for (uint guard = 0u; guard < MAX_LIST; guard += 1u)
    {
        uint end = braced_end(at + 1u, close, file);
        if (end == FAIL)
            return FAIL;
        if (kind_in(end, file) != TK_ELSE)
            return end;
        if (kind_in(end + 1u, file) == TK_IF)
        {
            at = end + 1u;
            continue;
        }
        if (kind_in(end + 1u, file) != TK_LBRACE)
            return FAIL;
        return group_end(end + 1u, file);
    }
    return FAIL;
}

// The token after the statement that starts at `s` in the block that
// closes at `close`: after its `;` or its last block. A last expression
// without `;` ends at `close`.
uint statement_end(uint s, uint close, uint file)
{
    uint kind = kind_in(s, file);
    if (kind == TK_WHILE || kind == TK_FOR)
        return braced_end(s + 1u, close, file);
    if (kind == TK_IF)
        return chain_end(s, close, file);
    if (kind == TK_LBRACE)
        return group_end(s, file);
    if (kind == TK_MATCH)
    {
        uint end = braced_end(s + 1u, close, file);
        if (end != FAIL && kind_in(end, file) == TK_SEMICOLON)
            end += 1u;
        return end;
    }
    uint depth = 0u;
    for (uint at = s; at < close; at += 1u)
    {
        uint at_kind = kind_in(at, file);
        if (at_kind == FAIL)
            return FAIL;
        if (opens(at_kind))
            depth += 1u;
        else if (closes(at_kind))
        {
            if (depth == 0u)
                return at;
            depth -= 1u;
        }
        else if (depth == 0u && at_kind == TK_SEMICOLON)
            return at + 1u;
    }
    return close;
}

// A block from `{` at `open` to the token `end` after its `}`.
void block(uint open, uint end, uint kind, uint owner)
{
    store(open, GR_ROLE, GROLE_BLOCK);
    store(open, GR_END, end);
    store(open, GR_OWNER, owner);
    store(open, GR_KIND, kind);
    store(end - 1u, GR_ROLE, GROLE_CLOSE);
    store(end - 1u, GR_OPEN, open);
}

uint rec(uint token, uint word)
{
    return records[token * GR_WORDS + word];
}

// The parameters `name: Type` between `(` at `open` and `)` at `close`.
void parameters(uint open, uint close, uint file)
{
    uint at = open + 1u;
    for (uint guard = 0u; guard < MAX_LIST && at < close; guard += 1u)
    {
        if (kind_in(at, file) == TK_IDENT && kind_in(at + 1u, file) == TK_COLON)
        {
            uint end = type_end(at + 2u, close, file);
            store(at, GR_ROLE, GROLE_PARAM);
            store(at, GR_END, end);
            at = end;
        }
        else
            at = type_end(at, close, file);
        if (kind_in(at, file) != TK_COMMA)
            return;
        at += 1u;
    }
}

// The statements of the body that opens at `open`, and of the blocks of
// its `while` and `if` statements. The walk keeps no stack: when a block
// ends, its records give the statement it belongs to, whose records give
// the next statement and the `}` of the block around it.
void statements(uint open, uint end, uint file)
{
    uint s = open + 1u;
    uint close = end - 1u;
    for (uint guard = 0u; guard < MAX_ITEM_TOKENS; guard += 1u)
    {
        if (s >= close)
        {
            uint block_open = rec(close, GR_OPEN);
            if (block_open == open)
                return;
            uint owner = rec(block_open, GR_OWNER);
            uint owner_end = rec(owner, GR_NEXT);
            // The next arm of an `if` chain.
            if (rec(block_open, GR_KIND) == BK_IF && kind_in(close + 1u, file) == TK_ELSE)
            {
                uint arm = kind_in(close + 2u, file) == TK_IF ? first_brace(close + 3u, owner_end, file) : close + 2u;
                uint arm_end = arm == FAIL || kind_in(arm, file) != TK_LBRACE ? FAIL : group_end(arm, file);
                if (arm_end != FAIL && arm_end <= owner_end)
                {
                    block(arm, arm_end, BK_IF, owner);
                    s = arm + 1u;
                    close = arm_end - 1u;
                    continue;
                }
            }
            s = owner_end;
            close = rec(owner, GR_CLOSE);
            continue;
        }
        uint next = statement_end(s, close, file);
        if (next == FAIL || next <= s || next > close)
        {
            // Brackets that do not match: the rest of the block is not read.
            s = close;
            continue;
        }
        store(s, GR_NEXT, next);
        store(s, GR_CLOSE, close);
        uint kind = kind_in(s, file);
        uint statement = s;
        s = next;
        if (kind == TK_LET)
        {
            store(statement, GR_ROLE, GROLE_LET);
            bool typed = kind_in(statement + 2u, file) == TK_COLON;
            store(statement, GR_END, typed ? type_end(statement + 3u, next, file) : 0u);
        }
        else if (kind == TK_YIELD)
        {
            store(statement, GR_ROLE, GROLE_YIELD);
            if (kind_in(next - 1u, file) == TK_SEMICOLON && next - 1u > statement)
            {
                store(next - 1u, GR_ROLE, GROLE_YIELD_END);
                store(next - 1u, GR_OPEN, statement);
            }
        }
        else if (kind == TK_RETURN)
            store(statement, GR_ROLE, GROLE_RETURN);
        else if (kind == TK_WHILE || kind == TK_FOR || kind == TK_IF)
        {
            uint body = first_brace(statement + 1u, next, file);
            uint body_end = body == FAIL ? FAIL : group_end(body, file);
            if (body_end == FAIL || body_end > next)
                continue;
            block(body, body_end, kind == TK_WHILE ? BK_WHILE : (kind == TK_FOR ? BK_FOR : BK_IF), statement);
            // A `for` body is no statement position.
            if (kind != TK_FOR)
            {
                s = body + 1u;
                close = body_end - 1u;
            }
        }
    }
}

// Every loop of the body, also those a statement walk does not reach.
void loops(uint open, uint end, uint file)
{
    for (uint at = open + 1u; at + 1u < end; at += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind != TK_WHILE && kind != TK_FOR)
            continue;
        uint body = first_brace(at + 1u, end - 1u, file);
        if (body == FAIL)
            continue;
        uint body_end = group_end(body, file);
        if (body_end != FAIL)
            block(body, body_end, kind == TK_WHILE ? BK_WHILE : BK_FOR, at);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gRead.token_count || token_kind(tokens_out, t) != TK_GEN)
        return;
    uint file = token_file_id[t];
    if (kind_in(t + 1u, file) != TK_FN || kind_in(t + 2u, file) != TK_IDENT)
        return;
    uint flags = t > 0u && kind_in(t - 1u, file) == TK_PUB ? GF_PUBLIC : 0u;
    uint at = t + 3u;
    if (kind_in(at, file) == TK_LT)
    {
        flags |= GF_GENERIC;
        at = type_end(at + 1u, MAX_ITEM_TOKENS, file) + 1u;
    }
    if (kind_in(at, file) != TK_LPAREN)
        return;
    uint params_end = group_end(at, file);
    if (params_end == FAIL)
        return;
    uint open = first_brace(params_end, params_end + MAX_ITEM_TOKENS, file);
    if (open == FAIL)
        return;
    uint end = group_end(open, file);
    if (end == FAIL)
        return;
    if (kind_in(params_end, file) != TK_ARROW)
        flags |= GF_NO_TYPE;
    for (uint between = params_end; between < open; between += 1u)
    {
        uint kind = kind_in(between, file);
        if (kind == TK_WHERE || kind == TK_REQUIRES || kind == TK_ENSURES)
            flags |= GF_WHERE;
    }
    store(t, GR_ROLE, GROLE_GEN);
    store(t, GR_END, end);
    store(t, GR_OPEN, open);
    store(t, GR_OWNER, params_end - 1u);
    store(t, GR_KIND, flags);
    parameters(at, params_end - 1u, file);
    loops(open, end, file);
    block(open, end, BK_BODY, 0u);
    statements(open, end, file);
}
