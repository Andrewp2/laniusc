// Shared layout of the machine expansion. A `machine` item becomes an enum of
// its states, a struct, a constructor and an impl. The kernels read the parse
// tree and write per-token records, then every token writes the pieces of
// text it stands for.
module machine_common;

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
