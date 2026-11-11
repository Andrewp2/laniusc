// Per token: the names a machine refers to, resolved, and the rules a token
// can check from its own place. A machine finds its start state, an enum
// finds the machines whose events it is, a `goto` finds its target and sets
// one bit of the transition graph. Every broken rule goes to the status
// words; the kernels after this one check the rules that need these names.
import gpu_index;
import byte_packing;
import generated_token_ids;
import machine_common;

struct ResolveParams
{
    uint token_count;
    uint machine_count;
    uint explain_word;
    uint explain_key;
};

ConstantBuffer<ResolveParams> gResolve;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> semantic_token_kinds;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint4> scan_b;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> states;
StructuredBuffer<uint> arms;
RWStructuredBuffer<uint> machine_info;
// Per state: one bit for each state of its machine that a `goto` in it names.
RWStructuredBuffer<uint> adjacency;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> detail;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * REC_WORDS + word];
}

uint raw(uint token)
{
    return token_kind(tokens_out, token);
}

uint semantic(uint token)
{
    return semantic_token_kinds[token + 1u];
}

bool same(uint a, uint b)
{
    return same_token_text(tokens_out, in_bytes, a, b);
}

void raise(uint word, uint token, uint code, uint a, uint b, uint number)
{
    machine_error(status, detail, tokens_out, gResolve.explain_word, gResolve.explain_key, word, token, code, a, b,
                  number);
}

void fail(uint token, uint code)
{
    raise(STATUS_TOKENS, token, code, 0u, 0u, 0u);
}

// Whether the `count` bytes of token `t` from `offset` are the bytes packed
// in `low` and `high`, least significant first.
bool text_at(uint t, uint offset, uint low, uint high, uint count)
{
    if (token_len(tokens_out, t) < offset + count)
        return false;
    for (uint i = 0u; i < count; i += 1u)
    {
        uint expected = i < 4u ? (low >> (i * 8u)) & 255u : (high >> ((i - 4u) * 8u)) & 255u;
        if (token_byte(tokens_out, in_bytes, t, offset + i) != expected)
            return false;
    }
    return true;
}

// Whether the event type of the machine at `head` is one integer type.
bool integer_event(uint head)
{
    uint name = head + 3u;
    if (rec(head, REC_EVENT_END) != name + 1u)
        return false;
    uint len = token_len(tokens_out, name);
    uint first = token_byte(tokens_out, in_bytes, name, 0u);
    if (first != 105u && first != 117u)
        return false;
    // "8", "16", "32", "64", "size"
    if (len == 2u)
        return text_at(name, 1u, 0x38u, 0u, 1u);
    if (len == 3u)
        return text_at(name, 1u, 0x3631u, 0u, 2u) || text_at(name, 1u, 0x3233u, 0u, 2u) ||
               text_at(name, 1u, 0x3436u, 0u, 2u);
    return len == 5u && text_at(name, 1u, 0x657a6973u, 0u, 4u);
}

uint field_count(uint state)
{
    return scan_b[rec(state, REC_BLOCK)].y - scan_b[state].y;
}

void check_machine(uint head)
{
    uint flags = rec(head, REC_FLAGS);
    uint first = scan_a[head].y;
    uint count = scan_a[rec(head, REC_END) - 1u].y - first;
    uint ordinal = scan_a[head].x - 1u;
    if (count > MAX_STATES)
        fail((flags & FLAG_PUBLIC) != 0u ? head - 1u : head, E_TOO_MANY_STATES);
    if ((flags & FLAG_SECOND_OUTPUT) != 0u)
        fail(rec(head, REC_OUTPUT_END), E_SECOND_OUTPUT);

    uint start = rec(head, REC_START);
    uint found = 0u;
    uint bound = min(count, MAX_STATES);
    for (uint k = 0u; k < bound; k += 1u)
    {
        uint state = states[first + k];
        if (same(state + 1u, start))
        {
            found = state;
            break;
        }
    }
    if (found == 0u)
        fail(start, E_NO_STATE);
    else if (field_count(found) != 0u)
        fail(start, E_START_DATA);
    machine_info[ordinal * INFO_WORDS + INFO_START] = found;
    machine_info[ordinal * INFO_WORDS + INFO_INTEGER] = integer_event(head) ? 1u : 0u;
}

// The enum named at `name` is the event type of every machine of its file
// that names it.
void bind_enum(uint name)
{
    uint file = token_file_id[name];
    uint lo = 0u;
    uint hi = gResolve.machine_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (token_file_id[machines[mid]] < file)
            lo = mid + 1u;
        else
            hi = mid;
    }
    for (uint k = lo; k < gResolve.machine_count && k - lo < MAX_LIST; k += 1u)
    {
        uint head = machines[k];
        if (token_file_id[head] != file)
            break;
        if (rec(head, REC_EVENT_END) == head + 4u && same(head + 3u, name))
            machine_info[k * INFO_WORDS + INFO_ENUM] = name;
    }
}

void check_state(uint state, uint head)
{
    uint first = scan_a[head].y;
    uint index = scan_a[state].y - 1u - first;
    uint bound = min(index, MAX_STATES);
    for (uint k = 0u; k < bound; k += 1u)
    {
        if (same(states[first + k] + 1u, state + 1u))
        {
            fail(state + 1u, E_DUPLICATE_STATE);
            break;
        }
    }
}

void check_transition(uint t, MachinePlace place)
{
    if (place.arm == MC_NONE)
    {
        fail(t, E_TRANSITION_OUTSIDE);
        return;
    }
    uint head = place.machine;
    uint state = place.state;
    uint body = rec(place.arm, REC_ARROW) + 1u;
    if (t != body)
    {
        // A statement of a block arm: it starts a statement and `;` ends it.
        uint before = raw(t - 1u);
        bool starts = before == TK_LBRACE || before == TK_RBRACE || before == TK_SEMICOLON;
        if (semantic(body) != TK_IF_LBRACE || !starts)
        {
            fail(t, E_TRANSITION_VALUE);
            return;
        }
        if (raw(rec(t, REC_END)) != TK_SEMICOLON)
        {
            fail(t, E_TRANSITION_SEMICOLON);
            return;
        }
    }
    bool output = (rec(head, REC_FLAGS) & FLAG_OUTPUT) != 0u;
    uint with_token = rec(t, REC_WITH);
    if (with_token != 0u && !output)
        fail(with_token, E_WITH_NO_OUTPUT);
    if (with_token == 0u && output)
        fail(t, E_NEEDS_WITH);
    if (semantic(t) != TK_GOTO)
        return;

    uint first = scan_a[head].y;
    uint count = min(scan_a[rec(head, REC_END) - 1u].y - first, MAX_STATES);
    uint target = MC_NONE;
    for (uint k = 0u; k < count; k += 1u)
    {
        if (same(states[first + k] + 1u, t + 1u))
        {
            target = k;
            break;
        }
    }
    if (target == MC_NONE)
    {
        fail(t + 1u, E_NO_STATE);
        return;
    }
    uint source = scan_a[state].y - 1u - first;
    if (source < MAX_STATES)
    {
        uint prior;
        InterlockedOr(adjacency[(first + source) * STATE_ROW_WORDS + (target >> 5u)], 1u << (target & 31u), prior);
    }
    // `run` keeps a state's data in locals, so a transition to the same
    // state assigns one value to each.
    uint args_close = rec(t, REC_ARGS_CLOSE);
    if (!output && target == source && args_close != 0u)
    {
        uint fields = field_count(state);
        if (scan_b[args_close].z - scan_b[t].z != fields)
            raise(STATUS_TOKENS, t + 2u, E_ARGUMENT_COUNT, t + 1u, 0u, fields);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gResolve.token_count)
        return;
    uint role = rec(t, REC_ROLE);
    uint kind = raw(t);
    if (role == ROLE_ENUM)
    {
        bind_enum(t);
        return;
    }
    MachinePlace place = machine_place(records, scan_a, scan_b, machines, states, arms, t);
    if (role == ROLE_TRANSITION)
    {
        check_transition(t, place);
        return;
    }
    if (place.machine == MC_NONE)
        return;
    if (role == ROLE_MACHINE)
    {
        check_machine(t);
        return;
    }
    if (place.state == MC_NONE)
        return;
    if (role == ROLE_STATE)
    {
        check_state(t, place.machine);
        return;
    }
    uint meaning = semantic(t);
    if ((meaning == TK_PARAM_SELF_VALUE || meaning == TK_PARAM_SELF_REF_VALUE) && t < rec(place.state, REC_BLOCK))
        fail(t, E_STATE_DATA);
    if (place.arm == MC_NONE)
        return;

    uint body = rec(place.arm, REC_ARROW) + 1u;
    uint body_kind = semantic(body);
    bool block_arm = body_kind == TK_IF_LBRACE;
    if (t == place.arm && !block_arm && body_kind != TK_GOTO && body_kind != TK_STAY)
        fail(body, E_ARM_BODY);
    if (block_arm && t > body)
    {
        if (kind == TK_RETURN)
            fail(t, E_RETURN);
        // The `}` that closes the arm's block is the arm's last token.
        if (kind == TK_RBRACE && scan_a[t].w + 1u == scan_a[body].w && t + 1u != rec(place.arm, REC_END))
            fail(t + 1u, E_BLOCK_ARM_END);
    }
}
