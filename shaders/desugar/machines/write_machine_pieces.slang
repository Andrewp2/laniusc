// Per token of a machine: the pieces of generated text it stands for, in each
// section of its machine. The kernel runs twice with the same control flow:
// first it counts the pieces of each section, then it writes them at the
// positions the prefix sums of those counts give.
//
// A machine's text is its sections in order, and a section holds the pieces
// of the machine's tokens in token order. The pieces of a machine go where
// its item stood: their owner is the item's first token, and the counting
// run marks the item's tokens to drop (desugaring_layout.slang).
import shared.buffers.gpu_index;
import shared.buffers.byte_packing;
import shared.syntax.generated_token_ids;
import machine_layout;
import desugar.tokens.desugaring_layout;

struct PieceParams
{
    uint edit_tokens;
    uint write;
    uint machine_count;
    uint reserved1;
};

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

ConstantBuffer<PieceParams> gPieces;
StructuredBuffer<TokenOut> tokens_out;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> records;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
// Inclusive prefix sums: arms of states, fields, arguments of transitions.
StructuredBuffer<uint4> scan_b;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> states;
StructuredBuffer<uint> transitions;
StructuredBuffer<uint> arms;
StructuredBuffer<uint> fields;
StructuredBuffer<uint> arguments;
StructuredBuffer<uint4> span_scan;
// Inclusive prefix sums of the piece counts, read by the writing run.
StructuredBuffer<uint4> count_scan0;
StructuredBuffer<uint4> count_scan1;
RWStructuredBuffer<uint4> counts0;
RWStructuredBuffer<uint4> counts1;
RWStructuredBuffer<uint4> pieces;
RWStructuredBuffer<uint> piece_owner;
RWStructuredBuffer<uint> drop;

static const uint DISPATCH_X_STRIDE = 16776960u;

struct Cursor
{
    uint base;
    uint count;
    uint owner;
};

struct Machine
{
    uint head;
    uint name;
    uint close;
    uint event_end;
    uint output_end;
    uint flags;
};

struct State
{
    uint head;
    uint name;
    uint block;
    uint close;
    uint first_field;
    uint field_count;
};

uint rec(uint token, uint word)
{
    return records[token * REC_WORDS + word];
}


uint start_of(uint token)
{
    return tokens_out[token].start;
}

uint end_of(uint token)
{
    TokenOut row = tokens_out[token];
    return row.start + row.len;
}

void put(inout Cursor cur, uint count, uint kind, uint value, uint anchor)
{
    if (gPieces.write != 0u)
    {
        uint at = cur.base + cur.count;
        pieces[at] = uint4(count, kind, value, anchor);
        piece_owner[at] = cur.owner;
    }
    cur.count += 1u;
}

void text(inout Cursor cur, uint id, uint anchor)
{
    put(cur, 1u, PIECE_CONST, id, anchor);
}

// A copy of tokens `[first, end)`.
void span(inout Cursor cur, uint first, uint end)
{
    put(cur, end > first ? end - first : 0u, PIECE_RANGE, first, first);
}

void token(inout Cursor cur, uint t)
{
    put(cur, 1u, PIECE_RANGE, t, t);
}

void number(inout Cursor cur, uint value, uint anchor)
{
    put(cur, 1u, PIECE_NUMBER, value, anchor);
}

void snake(inout Cursor cur, uint name)
{
    put(cur, 1u, PIECE_SNAKE, 0u, name);
}

bool same_text(uint a, uint b)
{
    TokenOut left = tokens_out[a];
    TokenOut right = tokens_out[b];
    if (left.len != right.len)
        return false;
    uint len = min(left.len, MAX_NAME);
    for (uint i = 0u; i < len; i += 1u)
    {
        if (byte_address_load_u8(in_bytes, left.start + i) != byte_address_load_u8(in_bytes, right.start + i))
            return false;
    }
    return true;
}

Machine machine_at(uint head)
{
    Machine m;
    m.head = head;
    m.name = head + 1u;
    m.close = rec(head, REC_END) - 1u;
    m.event_end = rec(head, REC_EVENT_END);
    m.output_end = rec(head, REC_OUTPUT_END);
    m.flags = rec(head, REC_FLAGS);
    return m;
}

bool has_output(Machine m)
{
    return (m.flags & FLAG_OUTPUT) != 0u;
}

State state_at(uint head)
{
    State s;
    s.head = head;
    s.name = head + 1u;
    s.block = rec(head, REC_BLOCK);
    s.close = rec(head, REC_END) - 1u;
    s.first_field = scan_b[head].y;
    s.field_count = min(scan_b[s.block].y - s.first_field, MAX_LIST);
    return s;
}

uint field_of(State s, uint k)
{
    return fields[s.first_field + k];
}

// The type of the field or state datum named by token `name`.
void field_type(inout Cursor cur, uint name)
{
    span(cur, name + 2u, rec(name, REC_END));
}

void public_word(inout Cursor cur, Machine m)
{
    if ((m.flags & FLAG_PUBLIC) != 0u)
        text(cur, C_PUB, m.name);
}

void event_type(inout Cursor cur, Machine m)
{
    span(cur, m.head + 3u, m.event_end);
}

void returns(inout Cursor cur, Machine m)
{
    if (has_output(m))
    {
        text(cur, C_ARROW, m.name);
        span(cur, m.event_end + 1u, m.output_end);
    }
}

void match_word(inout Cursor cur, Machine m, uint anchor)
{
    text(cur, has_output(m) ? C_RETURN_MATCH : C_MATCH, anchor);
}

// `NameState::State`.
void state_path(inout Cursor cur, Machine m, uint state_name)
{
    token(cur, m.name);
    text(cur, C_STATE_PATH, state_name);
    token(cur, state_name);
}

// `(a, b)`: the state's data as a pattern or a payload.
void payload(inout Cursor cur, State s)
{
    if (s.field_count == 0u)
        return;
    text(cur, C_LPAREN, s.name);
    for (uint k = 0u; k < s.field_count; k += 1u)
    {
        if (k > 0u)
            text(cur, C_COMMA, s.name);
        token(cur, field_of(s, k));
    }
    text(cur, C_RPAREN, s.name);
}

// `a, b, `: the state's data as leading call arguments.
void data_arguments(inout Cursor cur, State s)
{
    for (uint k = 0u; k < s.field_count; k += 1u)
    {
        token(cur, field_of(s, k));
        text(cur, C_COMMA, s.name);
    }
}

void machine_head(inout Cursor cur, uint ch, Machine m)
{
    if (ch == CH_ENUM)
    {
        public_word(cur, m);
        text(cur, C_ENUM, m.name);
        token(cur, m.name);
        text(cur, C_STATE_OPEN, m.name);
    }
    else if (ch == CH_STRUCT)
    {
        public_word(cur, m);
        text(cur, C_STRUCT, m.name);
        token(cur, m.name);
        text(cur, C_OPEN, m.name);
    }
    else if (ch == CH_START_HEAD)
    {
        public_word(cur, m);
        text(cur, C_FN, m.name);
        snake(cur, m.name);
        text(cur, C_START_FN, m.name);
    }
    else if (ch == CH_STEP)
    {
        public_word(cur, m);
        text(cur, C_IMPL, m.name);
        token(cur, m.name);
        text(cur, C_IMPL_OPEN, m.name);
        public_word(cur, m);
        text(cur, C_STEP, m.name);
        event_type(cur, m);
        text(cur, C_RPAREN, m.name);
        returns(cur, m);
        text(cur, C_BODY_OPEN, m.name);
        match_word(cur, m, m.name);
        text(cur, C_MATCH_STATE, m.name);
    }
    else if (ch == CH_RUN && !has_output(m))
    {
        text(cur, C_INDENT4, m.name);
        public_word(cur, m);
        text(cur, C_RUN_HEAD, m.name);
        event_type(cur, m);
        text(cur, C_RUN_LOOP, m.name);
    }
}

void machine_field(inout Cursor cur, uint ch, Machine m, uint name)
{
    if (ch == CH_STRUCT)
    {
        token(cur, name);
        text(cur, C_COLON, name);
        field_type(cur, name);
        text(cur, C_COMMA, name);
    }
    else if (ch == CH_START_HEAD)
    {
        if (scan_b[name].y - scan_b[m.head].y > 1u)
            text(cur, C_COMMA, name);
        token(cur, name);
        text(cur, C_COLON, name);
        field_type(cur, name);
    }
    else if (ch == CH_START_BODY)
    {
        token(cur, name);
        text(cur, C_COLON, name);
        token(cur, name);
        text(cur, C_COMMA, name);
    }
}

void machine_close(inout Cursor cur, uint ch, Machine m)
{
    if (ch == CH_ENUM)
    {
        text(cur, C_CLOSE, m.name);
    }
    else if (ch == CH_STRUCT)
    {
        text(cur, C_STATE_FIELD, m.name);
        token(cur, m.name);
        text(cur, C_STRUCT_END, m.name);
    }
    else if (ch == CH_START_HEAD)
    {
        text(cur, C_START_RETURNS, m.name);
        token(cur, m.name);
        text(cur, C_START_BODY, m.name);
        token(cur, m.name);
        text(cur, C_OPEN, m.name);
    }
    else if (ch == CH_START_BODY)
    {
        text(cur, C_STATE_FIELD, m.name);
        token(cur, m.name);
        text(cur, C_STATE_PATH, m.name);
        token(cur, rec(m.head, REC_START));
        text(cur, C_START_END, m.name);
    }
    else if (ch == CH_STEP)
    {
        text(cur, C_STEP_END, m.name);
        public_word(cur, m);
        text(cur, C_STATE_FN, m.name);
        token(cur, m.name);
        text(cur, C_STATE_FN_END, m.name);
    }
    else if (ch == CH_RUN && !has_output(m))
    {
        text(cur, C_RUN_END, m.name);
    }
    else if (ch == CH_RUN_FNS)
    {
        text(cur, C_CLOSE, m.name);
    }
}

void state_head(inout Cursor cur, uint ch, Machine m, State s)
{
    bool output = has_output(m);
    if (ch == CH_ENUM)
    {
        token(cur, s.name);
    }
    else if (ch == CH_STEP)
    {
        text(cur, C_INDENT12, s.name);
        state_path(cur, m, s.name);
        payload(cur, s);
        text(cur, C_ARM_OPEN, s.name);
        if (output)
            text(cur, C_RETURN, s.name);
        text(cur, C_SELF_IN, s.name);
        token(cur, s.name);
        text(cur, C_LPAREN, s.name);
        data_arguments(cur, s);
        text(cur, C_EVENT_ARG, s.name);
        text(cur, output ? C_STEP_ARM_END_OUTPUT : C_STEP_ARM_END, s.name);
    }
    else if (ch == CH_STATE_FNS)
    {
        text(cur, C_IN_FN, s.name);
        token(cur, s.name);
        text(cur, C_SELF_PARAM, s.name);
    }
    else if (ch == CH_RUN && !output)
    {
        text(cur, C_INDENT16, s.name);
        state_path(cur, m, s.name);
        payload(cur, s);
        text(cur, C_RUN_CALL, s.name);
        token(cur, s.name);
        text(cur, C_LPAREN, s.name);
        data_arguments(cur, s);
        text(cur, C_RUN_ARGS, s.name);
    }
    else if (ch == CH_RUN_FNS && !output)
    {
        text(cur, C_RUN_FN, s.name);
        token(cur, s.name);
        text(cur, C_SELF_PARAM, s.name);
    }
}

void state_datum(inout Cursor cur, uint ch, Machine m, State s, uint name)
{
    uint k = scan_b[name].y - s.first_field - 1u;
    if (ch == CH_ENUM)
    {
        text(cur, k == 0u ? C_LPAREN : C_COMMA, s.name);
        field_type(cur, name);
    }
    else if (ch == CH_STATE_FNS)
    {
        token(cur, name);
        text(cur, C_COLON, name);
        field_type(cur, name);
        text(cur, C_COMMA, name);
    }
    else if (ch == CH_RUN_FNS && !has_output(m))
    {
        text(cur, C_DATA, name);
        number(cur, k, name);
        text(cur, C_COLON, name);
        field_type(cur, name);
        text(cur, C_COMMA, name);
    }
}

void state_open(inout Cursor cur, uint ch, Machine m, State s)
{
    if (ch == CH_ENUM)
    {
        if (s.field_count > 0u)
            text(cur, C_RPAREN, s.name);
        bool last = scan_a[s.head].y == scan_a[m.close].y;
        text(cur, last ? C_SPACE : C_COMMA, s.name);
    }
    else if (ch == CH_STATE_FNS)
    {
        text(cur, C_EVENT_PARAM, s.name);
        event_type(cur, m);
        text(cur, C_RPAREN, s.name);
        returns(cur, m);
        text(cur, C_BODY_OPEN, s.name);
        match_word(cur, m, s.name);
        text(cur, C_MATCH_EVENT, s.name);
    }
    else if (ch == CH_RUN_FNS && !has_output(m))
    {
        text(cur, C_EVENTS_PARAM, s.name);
        event_type(cur, m);
        text(cur, C_RUN_SIGNATURE, s.name);
        for (uint k = 0u; k < s.field_count; k += 1u)
        {
            uint name = field_of(s, k);
            text(cur, C_LET8, name);
            token(cur, name);
            text(cur, C_COLON, name);
            field_type(cur, name);
            text(cur, C_DATA_INIT, name);
            number(cur, k, name);
            text(cur, C_STATEMENT_END, name);
        }
        text(cur, C_RUN_STATE_LOOP, s.name);
        event_type(cur, m);
        text(cur, C_RUN_STATE_MATCH, s.name);
    }
}

void state_close(inout Cursor cur, uint ch, Machine m, State s)
{
    if (ch == CH_STATE_FNS)
    {
        text(cur, C_ARMS_END, s.name);
        text(cur, C_STEP_FN_END, s.name);
    }
    else if (ch == CH_RUN_FNS && !has_output(m))
    {
        text(cur, C_ARMS_END, s.name);
        text(cur, C_RUN_FN_END, s.name);
        state_path(cur, m, s.name);
        payload(cur, s);
        text(cur, C_RUN_FN_RETURN, s.name);
    }
}

// `goto State(args) with value` or `stay with value` at token `at`. In
// `step` it stores the next state and returns. In `run` a transition to the
// state's own loop assigns the data and continues; one to another state
// stores it and returns the position.
void transition(inout Cursor cur, bool run, Machine m, State s, uint at)
{
    bool is_goto = tokens_out[at].kind == TK_GOTO;
    uint target = at + 1u;
    uint end = rec(at, REC_END);
    uint with_token = rec(at, REC_WITH);
    uint args_close = rec(at, REC_ARGS_CLOSE);
    if (!run)
    {
        if (is_goto)
        {
            text(cur, C_SET_STATE, at);
            state_path(cur, m, target);
            if (args_close != 0u)
                span(cur, at + 2u, args_close + 1u);
            text(cur, C_SEMICOLON_SPACE, at);
        }
        if (with_token != 0u)
        {
            text(cur, C_RETURN, with_token);
            span(cur, with_token + 1u, end);
            text(cur, C_SEMICOLON, with_token);
        }
        else
        {
            text(cur, C_RETURN_NOTHING, at);
        }
        return;
    }
    if (!is_goto)
    {
        text(cur, C_CONTINUE, at);
        return;
    }
    if (!same_text(target, s.name))
    {
        text(cur, C_SET_STATE, at);
        state_path(cur, m, target);
        if (args_close != 0u)
            span(cur, at + 2u, args_close + 1u);
        text(cur, C_RUN_LEAVE, at);
        return;
    }
    if (args_close != 0u)
    {
        // Each value is computed from the old data before any is assigned.
        uint first = scan_b[at].z;
        uint count = min(scan_b[args_close].z - first, s.field_count);
        if (count == 1u)
        {
            uint value = arguments[first];
            token(cur, field_of(s, 0u));
            text(cur, C_ASSIGN, at);
            span(cur, value, rec(value, REC_END));
            text(cur, C_SEMICOLON_SPACE, at);
        }
        else
        {
            for (uint k = 0u; k < count; k += 1u)
            {
                uint value = arguments[first + k];
                text(cur, C_LET_NEXT, at);
                number(cur, k, at);
                text(cur, C_COLON, at);
                field_type(cur, field_of(s, k));
                text(cur, C_ASSIGN, at);
                span(cur, value, rec(value, REC_END));
                text(cur, C_SEMICOLON_SPACE, at);
            }
            for (uint k = 0u; k < count; k += 1u)
            {
                token(cur, field_of(s, k));
                text(cur, C_NEXT, at);
                number(cur, k, at);
                text(cur, C_SEMICOLON_SPACE, at);
            }
        }
    }
    text(cur, C_CONTINUE, at);
}

// The token after the last transition statement before the `count`-th
// transition of the pack, inside the block arm that opens at `open`.
uint copied_from(uint open, uint count)
{
    if (count > 0u)
    {
        uint previous = transitions[count - 1u];
        if (previous > open)
            return rec(previous, REC_END) + 1u;
    }
    return open + 1u;
}

// A token inside the arms of a state. `run` selects the text of the state's
// `run` loop; otherwise the text is the state's `step` handler.
void arm_token(inout Cursor cur, bool run, Machine m, State s, uint t, uint role)
{
    uint ordinal = scan_b[t].x;
    if (ordinal == 0u)
        return;
    uint arm = arms[ordinal - 1u];
    uint arm_end = rec(arm, REC_END);
    if (arm <= s.block || t >= arm_end)
        return;
    uint arrow = rec(arm, REC_ARROW);
    uint body = arrow + 1u;
    uint body_kind = tokens_out[body].kind;
    bool block_arm = body_kind == TK_LBRACE;
    bool transition_arm = body_kind == TK_GOTO || body_kind == TK_STAY;

    if (t == arm)
    {
        // Lanius patterns do not bind a whole value, so a binding arm
        // `c -> ...` becomes `_ -> { let c: Event = event; ... }`.
        TokenOut pattern = tokens_out[arm];
        uint first = byte_address_load_u8(in_bytes, pattern.start);
        bool binding = arrow == arm + 1u && (ascii_lower(first) || (first == 95u && pattern.len > 1u));
        text(cur, C_ARM_LINE, arm);
        if (binding)
        {
            text(cur, C_WILDCARD, arm);
            token(cur, arrow);
        }
        else
        {
            span(cur, arm, arrow + 1u);
        }
        text(cur, C_SPACE, arrow);
        if (!block_arm && !transition_arm)
            return;
        if (block_arm)
            token(cur, body);
        else
            text(cur, C_LBRACE, body);
        if (binding)
        {
            text(cur, C_LET, arm);
            token(cur, arm);
            text(cur, C_COLON, arm);
            event_type(cur, m);
            text(cur, C_BIND_END, arm);
        }
        if (transition_arm)
            text(cur, C_SPACE, body);
        return;
    }
    if (role == ROLE_TRANSITION)
    {
        if (t == body)
        {
            transition(cur, run, m, s, t);
            text(cur, C_ARM_CLOSE, t);
            text(cur, C_ARM_COMMA, arrow);
        }
        else if (block_arm && t > body)
        {
            span(cur, copied_from(body, scan_a[t].z - 1u), t);
            transition(cur, run, m, s, t);
        }
        return;
    }
    if (block_arm && t + 1u == arm_end)
    {
        span(cur, copied_from(body, scan_a[t].z), t + 1u);
        text(cur, C_ARM_COMMA, arrow);
    }
}

void emit(inout Cursor cur, uint ch, uint t, uint role, Machine m, uint state_head_token)
{
    if (t == m.head)
    {
        machine_head(cur, ch, m);
        return;
    }
    if (t == m.close)
    {
        machine_close(cur, ch, m);
        return;
    }
    bool in_state = state_head_token != MC_NONE && state_head_token > m.head && t < rec(state_head_token, REC_END);
    if (!in_state)
    {
        if (role == ROLE_FIELD)
            machine_field(cur, ch, m, t);
        return;
    }
    State s = state_at(state_head_token);
    if (t == s.head)
        state_head(cur, ch, m, s);
    else if (t < s.block)
    {
        if (role == ROLE_DATA)
            state_datum(cur, ch, m, s, t);
    }
    else if (t == s.block)
        state_open(cur, ch, m, s);
    else if (t == s.close)
        state_close(cur, ch, m, s);
    else if (ch == CH_STATE_FNS)
        arm_token(cur, false, m, s, t, role);
    else if (ch == CH_RUN_FNS && !has_output(m))
        arm_token(cur, true, m, s, t, role);
}

uint4 scan0_before(uint t)
{
    return t > 0u ? count_scan0[t - 1u] : uint4(0u, 0u, 0u, 0u);
}

uint4 scan1_before(uint t)
{
    return t > 0u ? count_scan1[t - 1u] : uint4(0u, 0u, 0u, 0u);
}

uint sum4(uint4 v)
{
    return v.x + v.y + v.z + v.w;
}

uint component(uint4 v, uint index)
{
    if (index == 0u)
        return v.x;
    if (index == 1u)
        return v.y;
    if (index == 2u)
        return v.z;
    return v.w;
}

// How many compact rows lie at or before the given source token.
uint edit_rows_through(uint t)
{
    uint machines_through = scan_a[t].x;
    if (machines_through == 0u)
        return 0u;
    uint k = machines_through - 1u;
    uint before = k == 0u ? 0u : span_scan[k - 1u].x;
    return min(span_scan[k].x, before + t - machines[k] + 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint index = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (index >= gPieces.edit_tokens)
        return;
    uint lo = 0u;
    uint hi = gPieces.machine_count;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (span_scan[mid].x <= index)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint first = lo == 0u ? 0u : span_scan[lo - 1u].x;
    uint head = machines[lo];
    uint t = head + index - first;
    bool write = gPieces.write != 0u;
    uint4 sums = scan_a[t];
    Machine m = machine_at(head);
    if (!write)
    {
        InterlockedOr(drop[t], 1u);
        if (t == head && (m.flags & FLAG_PUBLIC) != 0u)
            InterlockedOr(drop[t - 1u], 1u);
    }
    uint state_head_token = sums.y > 0u ? states[sums.y - 1u] : MC_NONE;
    uint role = rec(t, REC_ROLE);

    // The first piece of each section of this token: the pieces before the
    // machine, the machine's earlier sections, and the section's pieces of
    // the machine's earlier tokens.
    uint4 base0 = uint4(0u, 0u, 0u, 0u);
    uint4 base1 = uint4(0u, 0u, 0u, 0u);
    if (write)
    {
        uint4 head0 = scan0_before(first);
        uint4 head1 = scan1_before(first);
        uint end = edit_rows_through(m.close);
        uint4 width0 = scan0_before(end) - head0;
        uint4 width1 = scan1_before(end) - head1;
        uint before = sum4(head0) + sum4(head1);
        uint4 earlier0 = uint4(0u, width0.x, width0.x + width0.y, width0.x + width0.y + width0.z);
        uint first1 = sum4(width0);
        uint4 earlier1 = uint4(first1, first1 + width1.x, first1 + width1.x + width1.y,
                               first1 + width1.x + width1.y + width1.z);
        base0 = before + earlier0 + (scan0_before(index) - head0);
        base1 = before + earlier1 + (scan1_before(index) - head1);
    }

    uint n0 = 0u;
    uint n1 = 0u;
    uint n2 = 0u;
    uint n3 = 0u;
    uint n4 = 0u;
    uint n5 = 0u;
    uint n6 = 0u;
    uint n7 = 0u;
    for (uint ch = 0u; ch < CHANNELS; ch += 1u)
    {
        Cursor cur;
        cur.base = ch < 4u ? component(base0, ch) : component(base1, ch - 4u);
        cur.count = 0u;
        cur.owner = (m.flags & FLAG_PUBLIC) != 0u ? m.head - 1u : m.head;
        emit(cur, ch, t, role, m, state_head_token);
        if (ch == 0u)
            n0 = cur.count;
        else if (ch == 1u)
            n1 = cur.count;
        else if (ch == 2u)
            n2 = cur.count;
        else if (ch == 3u)
            n3 = cur.count;
        else if (ch == 4u)
            n4 = cur.count;
        else if (ch == 5u)
            n5 = cur.count;
        else if (ch == 6u)
            n6 = cur.count;
        else
            n7 = cur.count;
    }
    if (!write)
    {
        counts0[index] = uint4(n0, n1, n2, n3);
        counts1[index] = uint4(n4, n5, n6, n7);
    }
}
