// Per token: the record of the machine construct that starts at the token,
// read from the token stream (machine_common.slang has the layout).
//
// A `goto` or `stay` token reads its own transition: the target, the
// arguments, `with` and the end of the expression. A `machine` token reads
// its whole item in one thread: the header, the fields, `start` and each
// state with its data and arms. An `enum` token reads its name and
// variants. Arm bodies, patterns and `with` values are read only as far as
// their brackets and the `,` or `;` that ends them; the parser reads them
// where the expansion puts them.
//
// An item is recorded only when all of it matches the grammar
// (grammar/lanius.bnf, M6 and `enum_item`). The thread reads it once to
// check and once to write, so a malformed item leaves no records, and the
// parser reports it.
import gpu_index;
import generated_token_ids;
import machine_common;

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
// Bounds the loops of one item. No item of a program that fits the
// compiler's limits reaches them.
static const uint MAX_ITEM_TOKENS = 1u << 22u;
static const uint MAX_TYPE_NESTING = 30u;

// The kind of token `t` when it lies in file `file`, otherwise FAIL.
uint kind_in(uint t, uint file)
{
    if (t >= gRead.token_count || token_file_id[t] != file)
        return FAIL;
    return token_kind(tokens_out, t);
}

void store(bool write, uint token, uint word, uint value)
{
    if (write && token < gRead.token_count)
        records[token * REC_WORDS + word] = value;
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

// The end of the expression, pattern or value that starts at `t`: the first
// `,` or `;` outside brackets, or the bracket that closes around it.
uint expression_end(uint t, uint file)
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
            if (depth == 0u)
                return at;
            depth -= 1u;
        }
        else if (depth == 0u && (kind == TK_COMMA || kind == TK_SEMICOLON))
            return at;
    }
    return FAIL;
}

// The token after the type that starts at `t`, or FAIL:
//   type  = `&` [`mut`] type | `[` type (`]` | `;` length `]`) | `!`
//         | path [`<` argument {`,` argument} [`,`] `>`]
//   path  = name {`::` name}
// An argument is a type or a constant. `>>` closes two lists.
uint type_end(uint t, uint file)
{
    // Bit k of `lists` is set when open list k is `<` and clear for `[`.
    uint lists = 0u;
    uint open = 0u;
    uint at = t;
    for (uint guard = 0u; guard < 4096u; guard += 1u)
    {
        // One type or argument.
        uint kind = kind_in(at, file);
        if (kind == TK_AMPERSAND)
        {
            at += 1u;
            if (kind_in(at, file) == TK_MUT)
                at += 1u;
            continue;
        }
        if (kind == TK_LBRACKET)
        {
            if (open == MAX_TYPE_NESTING)
                return FAIL;
            lists &= ~(1u << open);
            open += 1u;
            at += 1u;
            continue;
        }
        if (kind == TK_NOT)
            at += 1u;
        else if (kind == TK_INT && open > 0u && ((lists >> (open - 1u)) & 1u) != 0u)
            at += 1u;
        else if (kind == TK_MINUS && open > 0u && ((lists >> (open - 1u)) & 1u) != 0u && kind_in(at + 1u, file) == TK_INT)
            at += 2u;
        else if (kind == TK_IDENT)
        {
            at += 1u;
            while (kind_in(at, file) == TK_COLON && kind_in(at + 1u, file) == TK_COLON &&
                   kind_in(at + 2u, file) == TK_IDENT)
                at += 3u;
            if (kind_in(at, file) == TK_LT)
            {
                if (open == MAX_TYPE_NESTING)
                    return FAIL;
                lists |= 1u << open;
                open += 1u;
                at += 1u;
                continue;
            }
        }
        else
            return FAIL;

        // After a whole type or argument: close the lists it ends.
        for (uint close = 0u; close < 4096u; close += 1u)
        {
            if (open == 0u)
                return at;
            bool angle = ((lists >> (open - 1u)) & 1u) != 0u;
            uint next = kind_in(at, file);
            if (angle)
            {
                if (next == TK_COMMA && kind_in(at + 1u, file) == TK_GT)
                {
                    at += 2u;
                    open -= 1u;
                    continue;
                }
                if (next == TK_COMMA)
                {
                    at += 1u;
                    break;
                }
                if (next == TK_GT)
                {
                    at += 1u;
                    open -= 1u;
                    continue;
                }
                if (next == TK_SHR && open >= 2u && ((lists >> (open - 2u)) & 1u) != 0u)
                {
                    at += 1u;
                    open -= 2u;
                    continue;
                }
                return FAIL;
            }
            if (next == TK_RBRACKET)
            {
                at += 1u;
                open -= 1u;
                continue;
            }
            if (next == TK_SEMICOLON)
            {
                // The length: a constant or a path to one.
                at += 1u;
                uint length = kind_in(at, file);
                if (length == TK_INT)
                    at += 1u;
                else if (length == TK_IDENT)
                {
                    at += 1u;
                    while (kind_in(at, file) == TK_COLON && kind_in(at + 1u, file) == TK_COLON &&
                           kind_in(at + 2u, file) == TK_IDENT)
                        at += 3u;
                }
                else
                    return FAIL;
                if (kind_in(at, file) != TK_RBRACKET)
                    return FAIL;
                at += 1u;
                open -= 1u;
                continue;
            }
            return FAIL;
        }
    }
    return FAIL;
}

// `goto Name [(arguments)] [with value]` or `stay [with value]` at `t`.
void read_transition(uint t, uint file)
{
    uint kind = kind_in(t, file);
    uint at = t + 1u;
    uint args_close = 0u;
    if (kind == TK_GOTO)
    {
        at = t + 2u;
        if (kind_in(at, file) == TK_LPAREN)
        {
            uint end = group_end(at, file);
            if (end == FAIL)
                return;
            args_close = end - 1u;
            // The first token of each argument.
            uint first = at + 1u;
            while (first < args_close)
            {
                uint after = expression_end(first, file);
                if (after == FAIL || after > args_close)
                    break;
                store(true, first, REC_ROLE, ROLE_ARGUMENT);
                store(true, first, REC_END, after);
                if (after == args_close)
                    break;
                first = after + 1u;
            }
            at = end;
        }
    }
    uint with_token = 0u;
    uint end = at;
    if (kind_in(at, file) == TK_WITH)
    {
        with_token = at;
        end = expression_end(at + 1u, file);
        if (end == FAIL)
            return;
    }
    store(true, t, REC_ROLE, ROLE_TRANSITION);
    store(true, t, REC_END, end);
    store(true, t, REC_WITH, with_token);
    store(true, t, REC_ARGS_CLOSE, args_close);
}

// The `machine` item at `head`. Returns false when it does not match the
// grammar; writes its records when `write` is set.
bool read_machine(uint head, uint file, bool write)
{
    if (kind_in(head + 1u, file) != TK_IDENT || kind_in(head + 2u, file) != TK_ON)
        return false;
    uint flags = head > 0u && kind_in(head - 1u, file) == TK_PUB ? FLAG_PUBLIC : 0u;
    uint event_end = type_end(head + 3u, file);
    if (event_end == FAIL)
        return false;
    uint at = event_end;
    uint output_end = 0u;
    for (uint outputs = 0u; kind_in(at, file) == TK_ARROW && outputs < 4096u; outputs += 1u)
    {
        uint end = type_end(at + 1u, file);
        if (end == FAIL)
            return false;
        if (outputs == 0u)
        {
            output_end = end;
            flags |= FLAG_OUTPUT;
        }
        else
            flags |= FLAG_SECOND_OUTPUT;
        at = end;
    }
    if (kind_in(at, file) != TK_LBRACE)
        return false;
    at += 1u;

    // `name: Type` fields, comma separated, with an optional trailing comma.
    for (uint guard = 0u; guard < MAX_ITEM_TOKENS; guard += 1u)
    {
        if (kind_in(at, file) != TK_IDENT || kind_in(at + 1u, file) != TK_COLON)
            break;
        uint end = type_end(at + 2u, file);
        if (end == FAIL)
            return false;
        store(write, at, REC_ROLE, ROLE_FIELD);
        store(write, at, REC_END, end);
        at = end;
        if (kind_in(at, file) != TK_COMMA)
            break;
        at += 1u;
    }

    if (kind_in(at, file) != TK_START || kind_in(at + 1u, file) != TK_IDENT ||
        kind_in(at + 2u, file) != TK_SEMICOLON)
        return false;
    uint start = at + 1u;
    at += 3u;

    // The states.
    for (uint guard = 0u; guard < MAX_ITEM_TOKENS; guard += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == TK_RBRACE)
            break;
        uint state_flags = 0u;
        if (kind == TK_FINAL)
        {
            state_flags = FLAG_FINAL;
            at += 1u;
        }
        uint state = at;
        if (kind_in(state, file) != TK_STATE || kind_in(state + 1u, file) != TK_IDENT)
            return false;
        at = state + 2u;
        if (kind_in(at, file) == TK_LPAREN)
        {
            state_flags |= FLAG_DATA;
            at += 1u;
            // Parameters, comma separated, with an optional trailing comma.
            for (uint param = 0u; param < MAX_ITEM_TOKENS; param += 1u)
            {
                uint p = kind_in(at, file);
                if (p == TK_RPAREN)
                    break;
                if (p == TK_IDENT && kind_in(at + 1u, file) == TK_COLON)
                {
                    uint end = type_end(at + 2u, file);
                    if (end == FAIL)
                        return false;
                    store(write, at, REC_ROLE, ROLE_DATA);
                    store(write, at, REC_END, end);
                    at = end;
                }
                else if (p == TK_SELF_VALUE)
                {
                    at += 1u;
                    if (kind_in(at, file) == TK_COLON)
                    {
                        at = type_end(at + 1u, file);
                        if (at == FAIL)
                            return false;
                    }
                }
                else if (p == TK_AMPERSAND)
                {
                    at += 1u;
                    if (kind_in(at, file) == TK_MUT)
                        at += 1u;
                    if (kind_in(at, file) != TK_SELF_VALUE)
                        return false;
                    at += 1u;
                }
                else
                    return false;
                uint next = kind_in(at, file);
                if (next == TK_COMMA)
                    at += 1u;
                else if (next != TK_RPAREN)
                    return false;
            }
            at += 1u;
        }
        uint block = at;
        if (kind_in(block, file) != TK_LBRACE)
            return false;
        at = block + 1u;
        // The arms: `pattern -> value`, comma separated, with an optional
        // trailing comma.
        for (uint arm_guard = 0u; arm_guard < MAX_ITEM_TOKENS; arm_guard += 1u)
        {
            if (kind_in(at, file) == TK_RBRACE)
                break;
            uint arm = at;
            uint arrow = FAIL;
            uint depth = 0u;
            for (uint p = arm; p - arm < MAX_ITEM_TOKENS; p += 1u)
            {
                uint k = kind_in(p, file);
                if (k == FAIL)
                    return false;
                if (opens(k))
                    depth += 1u;
                else if (closes(k))
                {
                    if (depth == 0u)
                        return false;
                    depth -= 1u;
                }
                else if (depth == 0u && k == TK_ARROW)
                {
                    arrow = p;
                    break;
                }
                else if (depth == 0u && (k == TK_COMMA || k == TK_SEMICOLON))
                    return false;
            }
            if (arrow == FAIL || arrow == arm)
                return false;
            uint end = expression_end(arrow + 1u, file);
            if (end == FAIL || end == arrow + 1u)
                return false;
            store(write, arm, REC_ROLE, ROLE_ARM);
            store(write, arm, REC_END, end);
            store(write, arm, REC_ARROW, arrow);
            uint after = kind_in(end, file);
            if (after == TK_COMMA)
                at = end + 1u;
            else if (after == TK_RBRACE)
                at = end;
            else
                return false;
        }
        if (kind_in(at, file) != TK_RBRACE)
            return false;
        store(write, state, REC_ROLE, ROLE_STATE);
        store(write, state, REC_END, at + 1u);
        store(write, state, REC_BLOCK, block);
        store(write, state, REC_FLAGS, state_flags);
        at += 1u;
    }
    if (kind_in(at, file) != TK_RBRACE)
        return false;
    store(write, head, REC_ROLE, ROLE_MACHINE);
    store(write, head, REC_END, at + 1u);
    store(write, head, REC_EVENT_END, event_end);
    store(write, head, REC_OUTPUT_END, output_end);
    store(write, head, REC_START, start);
    store(write, head, REC_FLAGS, flags);
    return true;
}

// The `enum` item at `head`: its name and the names of its variants.
bool read_enum(uint head, uint file, bool write)
{
    uint name = head + 1u;
    if (kind_in(name, file) != TK_IDENT)
        return false;
    // Type parameters and a `where` clause hold no brace.
    uint at = name + 1u;
    for (uint guard = 0u; guard < MAX_ITEM_TOKENS; guard += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == FAIL || kind == TK_SEMICOLON || kind == TK_RBRACE)
            return false;
        if (kind == TK_LBRACE)
            break;
        at += 1u;
    }
    at += 1u;
    for (uint guard = 0u; guard < MAX_ITEM_TOKENS; guard += 1u)
    {
        uint kind = kind_in(at, file);
        if (kind == TK_RBRACE)
            break;
        if (kind != TK_IDENT)
            return false;
        store(write, at, REC_ROLE, ROLE_VARIANT);
        at += 1u;
        if (kind_in(at, file) == TK_LPAREN)
        {
            at = group_end(at, file);
            if (at == FAIL)
                return false;
        }
        uint next = kind_in(at, file);
        if (next == TK_COMMA)
            at += 1u;
        else if (next != TK_RBRACE)
            return false;
    }
    if (kind_in(at, file) != TK_RBRACE)
        return false;
    store(write, name, REC_ROLE, ROLE_ENUM);
    store(write, name, REC_END, at + 1u);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gRead.token_count)
        return;
    uint kind = token_kind(tokens_out, t);
    uint file = token_file_id[t];
    if (kind == TK_GOTO || kind == TK_STAY)
        read_transition(t, file);
    else if (kind == TK_MACHINE)
    {
        if (read_machine(t, file, false))
            read_machine(t, file, true);
    }
    else if (kind == TK_ENUM)
    {
        if (read_enum(t, file, false))
            read_enum(t, file, true);
    }
}
