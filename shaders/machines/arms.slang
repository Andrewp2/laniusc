// Per token: for each arm of a state, the event it handles in full. For an
// enum event that is the variant its pattern names, when the pattern accepts
// every payload. For an integer event it is whether the arm accepts every
// value. The machine's first token checks that its event type is known.
import gpu_index;
import byte_packing;
import generated_token_ids;
import machine_common;

struct ArmParams
{
    uint token_count;
    uint reserved0;
    uint explain_word;
    uint explain_key;
};

ConstantBuffer<ArmParams> gArms;
StructuredBuffer<uint> tokens_out;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> scan_a;
// Inclusive prefix sums: arms of states, fields, arguments, enum variants.
StructuredBuffer<uint4> scan_b;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> states;
StructuredBuffer<uint> arms;
StructuredBuffer<uint> variants;
StructuredBuffer<uint> machine_info;
// Per arm of a state, by its ordinal. Enum events: one more than the index
// of the variant it handles, 0 when it handles none in full. Integer events:
// 1 when it accepts every value.
RWStructuredBuffer<uint> arm_event;
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

void raise(uint token, uint code, uint a)
{
    machine_error(status, detail, tokens_out, gArms.explain_word, gArms.explain_key, STATUS_TOKENS, token, code, a,
                  0u, 0u);
}

// A name that binds a value or `_`: a pattern that accepts everything.
bool binds(uint token)
{
    if (raw(token) != TK_IDENT)
        return false;
    uint first = token_byte(tokens_out, in_bytes, token, 0u);
    return first == 95u || ascii_lower(first);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gArms.token_count)
        return;
    uint role = rec(t, REC_ROLE);
    if (role == ROLE_MACHINE)
    {
        uint info = (scan_a[t].x - 1u) * INFO_WORDS;
        if (machine_info[info + INFO_ENUM] == 0u && machine_info[info + INFO_INTEGER] == 0u)
            raise(t + 3u, E_EVENT_TYPE, rec(t, REC_EVENT_END) - 1u);
        return;
    }
    if (role != ROLE_ARM)
        return;
    MachinePlace place = machine_place(records, scan_a, scan_b, machines, states, arms, t);
    if (place.arm != t)
        return;
    uint slot = scan_b[t].x - 1u;
    uint info = (scan_a[place.machine].x - 1u) * INFO_WORDS;
    uint event_enum = machine_info[info + INFO_ENUM];
    uint arrow = rec(t, REC_ARROW);
    bool single = arrow == t + 1u;
    if (machine_info[info + INFO_INTEGER] != 0u)
    {
        arm_event[slot] = single && binds(t) ? 1u : 0u;
        return;
    }
    if (single && raw(t) == TK_IDENT && token_len(tokens_out, t) == 1u &&
        token_byte(tokens_out, in_bytes, t, 0u) == 95u)
        raise(t, E_WILDCARD, place.state + 1u);
    if (event_enum == 0u)
    {
        arm_event[slot] = 0u;
        return;
    }

    // `Enum::Variant`, `Variant`, or either with a payload of names and `_`.
    uint name = t;
    for (uint guard = 0u; guard < MAX_LIST; guard += 1u)
    {
        if (name + 3u >= arrow || raw(name) != TK_IDENT || raw(name + 1u) != TK_COLON || raw(name + 2u) != TK_COLON)
            break;
        name += 3u;
    }
    bool whole = raw(name) == TK_IDENT;
    uint after = name + 1u;
    if (whole && after != arrow)
    {
        uint close = arrow - 1u;
        whole = after < close && raw(after) == TK_LPAREN && raw(close) == TK_RPAREN;
        uint item = after + 1u;
        for (uint guard = 0u; guard < MAX_LIST && whole && item < close; guard += 1u)
        {
            whole = binds(item) && (item + 1u == close || raw(item + 1u) == TK_COMMA);
            item += 2u;
        }
    }
    uint index = 0u;
    if (whole)
    {
        uint first = scan_b[event_enum].w;
        uint count = min(scan_b[rec(event_enum, REC_END) - 1u].w - first, MAX_LIST);
        for (uint v = 0u; v < count; v += 1u)
        {
            if (same_token_text(tokens_out, in_bytes, variants[first + v], name))
            {
                index = v + 1u;
                break;
            }
        }
    }
    arm_event[slot] = index;
}
