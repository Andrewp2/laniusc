// Shared layout of the machine expansion. A `machine` item becomes an enum of
// its states, a struct, a constructor and an impl. The kernels read the parse
// tree and write per-token records, then every token writes the pieces of
// text it stands for.
module machine_common;

import byte_packing;

public static const uint MC_NONE = 0xffffffffu;

// Words of one token record. Word 0 is the role; the rest depend on it.
public static const uint REC_WORDS = 6u;
public static const uint REC_ROLE = 0u;
// Every role: the token after the last token of the construct.
public static const uint REC_END = 1u;
// Machine: the token after the event type, the token after the output type
// (0 without one), the start state's name and the flags.
public static const uint REC_EVENT_END = 2u;
public static const uint REC_OUTPUT_END = 3u;
public static const uint REC_START = 4u;
public static const uint REC_FLAGS = 5u;
// State: the `{` of its arms. The flags share the machine's word.
public static const uint REC_BLOCK = 2u;
// Arm: its `->`.
public static const uint REC_ARROW = 2u;
// Transition: its `with` (0 without one) and the `)` of its arguments (0
// without any).
public static const uint REC_WITH = 2u;
public static const uint REC_ARGS_CLOSE = 3u;

// Roles. A role sits on the first token of its construct: the `machine` or
// `state` word, a field's name, an arm's pattern, `goto` or `stay`, the
// first token of a call argument.
public static const uint ROLE_MACHINE = 1u;
public static const uint ROLE_STATE = 2u;
public static const uint ROLE_FIELD = 3u;
public static const uint ROLE_DATA = 4u;
public static const uint ROLE_ARM = 5u;
public static const uint ROLE_TRANSITION = 6u;
public static const uint ROLE_ARGUMENT = 7u;
// The name of an enum declaration and the name of one of its variants.
public static const uint ROLE_ENUM = 8u;
public static const uint ROLE_VARIANT = 9u;

public static const uint FLAG_PUBLIC = 1u;
public static const uint FLAG_OUTPUT = 2u;
public static const uint FLAG_SECOND_OUTPUT = 4u;
public static const uint FLAG_FINAL = 1u;
public static const uint FLAG_DATA = 2u;

// The sections of a machine's text, in output order. Each is one channel of
// the piece layout: a token's pieces in a channel follow those of the tokens
// before it in the same machine.
public static const uint CH_ENUM = 0u;
public static const uint CH_STRUCT = 1u;
public static const uint CH_START_HEAD = 2u;
public static const uint CH_START_BODY = 3u;
public static const uint CH_STEP = 4u;
public static const uint CH_STATE_FNS = 5u;
public static const uint CH_RUN = 6u;
public static const uint CH_RUN_FNS = 7u;
public static const uint CHANNELS = 8u;

// Piece kinds. A piece row is `(length, kind, value, anchor token)`: a copy
// of source bytes from `value`, constant string `value`, the decimal digits
// of `value`, or the snake_case form of the anchor token.
public static const uint PIECE_COPY = 0u;
public static const uint PIECE_CONST = 1u;
public static const uint PIECE_NUMBER = 2u;
public static const uint PIECE_SNAKE = 3u;

// No well-formed program reaches these. They bound the loops of a kernel
// that runs before the host has read whether the parser accepted the files.
public static const uint MAX_LIST = 65536u;
public static const uint MAX_NAME = 65536u;

// Constant strings, in the order of the host table.
public static const uint C_PUB = 0u;
public static const uint C_ENUM = 1u;
public static const uint C_STATE_OPEN = 2u;
public static const uint C_STRUCT = 3u;
public static const uint C_OPEN = 4u;
public static const uint C_FN = 5u;
public static const uint C_START_FN = 6u;
public static const uint C_IMPL = 7u;
public static const uint C_IMPL_OPEN = 8u;
public static const uint C_STEP = 9u;
public static const uint C_RPAREN = 10u;
public static const uint C_ARROW = 11u;
public static const uint C_BODY_OPEN = 12u;
public static const uint C_RETURN_MATCH = 13u;
public static const uint C_MATCH = 14u;
public static const uint C_MATCH_STATE = 15u;
public static const uint C_INDENT4 = 16u;
public static const uint C_RUN_HEAD = 17u;
public static const uint C_RUN_LOOP = 18u;
public static const uint C_COLON = 19u;
public static const uint C_COMMA = 20u;
public static const uint C_LPAREN = 21u;
public static const uint C_SPACE = 22u;
public static const uint C_INDENT12 = 23u;
public static const uint C_STATE_PATH = 24u;
public static const uint C_ARM_OPEN = 25u;
public static const uint C_RETURN = 26u;
public static const uint C_SELF_IN = 27u;
public static const uint C_EVENT_ARG = 28u;
public static const uint C_STEP_ARM_END_OUTPUT = 29u;
public static const uint C_STEP_ARM_END = 30u;
public static const uint C_IN_FN = 31u;
public static const uint C_SELF_PARAM = 32u;
public static const uint C_INDENT16 = 33u;
public static const uint C_RUN_CALL = 34u;
public static const uint C_RUN_ARGS = 35u;
public static const uint C_RUN_FN = 36u;
public static const uint C_DATA = 37u;
public static const uint C_EVENT_PARAM = 38u;
public static const uint C_MATCH_EVENT = 39u;
public static const uint C_EVENTS_PARAM = 40u;
public static const uint C_RUN_SIGNATURE = 41u;
public static const uint C_LET8 = 42u;
public static const uint C_DATA_INIT = 43u;
public static const uint C_STATEMENT_END = 44u;
public static const uint C_RUN_STATE_LOOP = 45u;
public static const uint C_RUN_STATE_MATCH = 46u;
public static const uint C_ARM_LINE = 47u;
public static const uint C_WILDCARD = 48u;
public static const uint C_LBRACE = 49u;
public static const uint C_LET = 50u;
public static const uint C_BIND_END = 51u;
public static const uint C_ARM_CLOSE = 52u;
public static const uint C_ARM_COMMA = 53u;
public static const uint C_ARMS_END = 54u;
public static const uint C_STEP_FN_END = 55u;
public static const uint C_RUN_FN_END = 56u;
public static const uint C_RUN_FN_RETURN = 57u;
public static const uint C_CLOSE = 58u;
public static const uint C_STATE_FIELD = 59u;
public static const uint C_STRUCT_END = 60u;
public static const uint C_START_RETURNS = 61u;
public static const uint C_START_BODY = 62u;
public static const uint C_START_END = 63u;
public static const uint C_STEP_END = 64u;
public static const uint C_STATE_FN = 65u;
public static const uint C_STATE_FN_END = 66u;
public static const uint C_RUN_END = 67u;
public static const uint C_SET_STATE = 68u;
public static const uint C_SEMICOLON_SPACE = 69u;
public static const uint C_SEMICOLON = 70u;
public static const uint C_RETURN_NOTHING = 71u;
public static const uint C_CONTINUE = 72u;
public static const uint C_RUN_LEAVE = 73u;
public static const uint C_ASSIGN = 74u;
public static const uint C_LET_NEXT = 75u;
public static const uint C_NEXT = 76u;

// A machine has at most this many states: a row of the transition graph is
// this many bits.
public static const uint MAX_STATES = 256u;
public static const uint STATE_ROW_WORDS = 8u;

// Per machine: the name of the enum its events are (0 when no enum of the
// file has the event type's name), the first token of its start state (0
// when no state has that name), and whether its events are integers.
public static const uint INFO_WORDS = 3u;
public static const uint INFO_ENUM = 0u;
public static const uint INFO_START = 1u;
public static const uint INFO_INTEGER = 2u;

// The status words. Each holds the least `token << 5 | code` of one group of
// rules, and the host reports the first group that has an error: reserved
// names, the rules a token checks, the events a state handles, the graph.
public static const uint STATUS_RESERVED = 0u;
public static const uint STATUS_TOKENS = 1u;
public static const uint STATUS_EVENTS = 2u;
public static const uint STATUS_GRAPH = 3u;
// Not a rule: the first `gen` or `yield` token of the pack.
public static const uint STATUS_GENERATORS = 4u;

public static const uint E_RESERVED = 1u;

public static const uint E_TOO_MANY_STATES = 1u;
public static const uint E_SECOND_OUTPUT = 2u;
public static const uint E_DUPLICATE_STATE = 3u;
public static const uint E_NO_STATE = 4u;
public static const uint E_START_DATA = 5u;
public static const uint E_EVENT_TYPE = 6u;
public static const uint E_WILDCARD = 7u;
public static const uint E_ARM_BODY = 8u;
public static const uint E_BLOCK_ARM_END = 9u;
public static const uint E_RETURN = 10u;
public static const uint E_TRANSITION_SEMICOLON = 11u;
public static const uint E_WITH_NO_OUTPUT = 12u;
public static const uint E_NEEDS_WITH = 13u;
public static const uint E_ARGUMENT_COUNT = 14u;
public static const uint E_TRANSITION_OUTSIDE = 15u;
public static const uint E_TRANSITION_VALUE = 16u;
public static const uint E_STATE_DATA = 17u;

public static const uint E_MISSING_EVENT = 1u;
public static const uint E_MISSING_EVENT_OUTPUT = 2u;
public static const uint E_CATCH_ALL = 3u;

public static const uint E_UNREACHABLE = 1u;
public static const uint E_DEAD_END = 2u;
public static const uint E_FINAL_LEAVES = 3u;

// A token row is `(kind, start, length)`.
public uint token_kind(StructuredBuffer<uint> tokens, uint token)
{
    return tokens[token * 3u];
}

public uint token_start(StructuredBuffer<uint> tokens, uint token)
{
    return tokens[token * 3u + 1u];
}

public uint token_len(StructuredBuffer<uint> tokens, uint token)
{
    return tokens[token * 3u + 2u];
}

public uint token_byte(StructuredBuffer<uint> tokens, ByteAddressBuffer bytes, uint token, uint offset)
{
    return byte_address_load_u8(bytes, token_start(tokens, token) + offset);
}

public bool same_token_text(StructuredBuffer<uint> tokens, ByteAddressBuffer bytes, uint a, uint b)
{
    uint len = token_len(tokens, a);
    if (len != token_len(tokens, b))
        return false;
    uint left = token_start(tokens, a);
    uint right = token_start(tokens, b);
    len = min(len, MAX_NAME);
    for (uint i = 0u; i < len; i += 1u)
    {
        if (byte_address_load_u8(bytes, left + i) != byte_address_load_u8(bytes, right + i))
            return false;
    }
    return true;
}

// The machine, state and arm a token is inside, each by its first token.
public struct MachinePlace
{
    public uint machine;
    public uint state;
    public uint arm;
};

// `scan_a` holds the inclusive prefix sums of machines, states, transitions
// and bracket depth; `scan_b` those of the arms of states.
public MachinePlace machine_place(StructuredBuffer<uint> records, StructuredBuffer<uint4> scan_a,
                                  StructuredBuffer<uint4> scan_b, StructuredBuffer<uint> machines,
                                  StructuredBuffer<uint> states, StructuredBuffer<uint> arms, uint token)
{
    MachinePlace place;
    place.machine = MC_NONE;
    place.state = MC_NONE;
    place.arm = MC_NONE;
    uint4 sums = scan_a[token];
    if (sums.x == 0u)
        return place;
    uint machine = machines[sums.x - 1u];
    if (token >= records[machine * REC_WORDS + REC_END])
        return place;
    place.machine = machine;
    if (sums.y == 0u)
        return place;
    uint state = states[sums.y - 1u];
    if (state < machine || token >= records[state * REC_WORDS + REC_END])
        return place;
    place.state = state;
    uint ordinal = scan_b[token].x;
    if (ordinal == 0u)
        return place;
    uint arm = arms[ordinal - 1u];
    if (arm <= records[state * REC_WORDS + REC_BLOCK] || token >= records[arm * REC_WORDS + REC_END])
        return place;
    place.arm = arm;
    return place;
}

// Reports a broken rule at `token`. The status word keeps the least key. In
// the run that explains the error the host read, the thread that found it
// writes the spans the message names: the token, tokens `a` and `b`, and a
// number.
public void machine_error(RWStructuredBuffer<uint> status, RWStructuredBuffer<uint> detail,
                          StructuredBuffer<uint> tokens, uint explain_word, uint explain_key, uint word, uint token,
                          uint code, uint a, uint b, uint number)
{
    uint key = (token << 5u) | code;
    if (explain_word == word && explain_key == key)
    {
        detail[0u] = token_start(tokens, token);
        detail[1u] = token_len(tokens, token);
        detail[2u] = token_start(tokens, a);
        detail[3u] = token_len(tokens, a);
        detail[4u] = token_start(tokens, b);
        detail[5u] = token_len(tokens, b);
        detail[6u] = number;
    }
    uint prior;
    InterlockedMin(status[word], key, prior);
}

public bool ascii_upper(uint c)
{
    return c >= 65u && c <= 90u;
}

public bool ascii_lower(uint c)
{
    return c >= 97u && c <= 122u;
}

public bool ascii_digit(uint c)
{
    return c >= 48u && c <= 57u;
}

// Whether snake_case puts `_` before `current`: an upper-case letter after a
// lower-case letter or a digit, or the last upper-case letter of a run that
// a lower-case letter follows. A missing neighbour is 0.
public bool snake_boundary(uint previous, uint current, uint next)
{
    if (!ascii_upper(current))
        return false;
    return ascii_lower(previous) || ascii_digit(previous) || (ascii_upper(previous) && ascii_lower(next));
}
