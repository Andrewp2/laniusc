// Shared layout of the generator round of the desugaring. A `gen fn`
// becomes a `machine` with one state per `yield`, a function that constructs
// it and an impl with `next`. The kernels read the token stream into
// per-token records (read_generator_records.slang), then every piece of the machine's text is
// written by a thread of its own.
module generator_layout;

import byte_packing;

public static const uint GN_NONE = 0xffffffffu;

// Words of one token record. Word 0 is the role; the rest depend on it.
public static const uint GR_WORDS = 7u;
public static const uint GR_ROLE = 0u;
// Generator: the token after its body's `}`. Block: the token after its `}`.
// Let and parameter: the token after the type (0 for a let without one).
public static const uint GR_END = 1u;
// The first token of a statement: the first token of the next statement, or
// the `}` of the block after its last statement.
public static const uint GR_NEXT = 2u;
// Generator: its body's `{`. Block close: its `{`. Yield end: its `yield`.
public static const uint GR_OPEN = 3u;
// Generator: the `)` of its parameters. Block: the first token of the
// statement the block belongs to (0 for a generator's body).
public static const uint GR_OWNER = 4u;
// Generator: its flags. Block: its kind.
public static const uint GR_KIND = 5u;
// The first token of a statement: the `}` of the block the statement is in.
public static const uint GR_CLOSE = 6u;

// Roles. A role sits on the first token of its construct: `gen`, a
// parameter's name, `let`, `yield` and `return` at a statement position, the
// `;` of a yield statement, and the `{` and `}` of a block. Statement
// positions are those of a generator's body and of the blocks of its
// `while` and `if` statements.
public static const uint GROLE_GEN = 1u;
public static const uint GROLE_PARAM = 2u;
public static const uint GROLE_LET = 3u;
public static const uint GROLE_YIELD = 4u;
public static const uint GROLE_YIELD_END = 5u;
public static const uint GROLE_BLOCK = 6u;
public static const uint GROLE_CLOSE = 7u;
public static const uint GROLE_RETURN = 8u;

// Block kinds. A yield sits only in a generator's body and in the blocks of
// its `while` and `if` statements.
public static const uint BK_BODY = 1u;
public static const uint BK_WHILE = 2u;
public static const uint BK_IF = 3u;
public static const uint BK_FOR = 4u;

public static const uint GF_PUBLIC = 1u;
public static const uint GF_GENERIC = 2u;
public static const uint GF_NO_TYPE = 4u;
public static const uint GF_WHERE = 8u;

// No well-formed program reaches these. They bound the loops of a kernel.
public static const uint MAX_LIST = 65536u;
public static const uint MAX_NAME = 65536u;
public static const uint MAX_DEPTH = 4096u;

// Constant strings, in the order of the host table.
public static const uint GC_EMPTY = 0u;
public static const uint GC_PUB = 1u;
public static const uint GC_ENUM = 2u;
public static const uint GC_RESUME_ENUM = 3u;
public static const uint GC_MACHINE = 4u;
public static const uint GC_ON = 5u;
public static const uint GC_RESUME_OUTPUT = 6u;
public static const uint GC_OUTPUT_END = 7u;
public static const uint GC_INDENT = 8u;
public static const uint GC_FIELD_END = 9u;
public static const uint GC_START_STATE = 10u;
public static const uint GC_ARM = 11u;
public static const uint GC_LET = 12u;
public static const uint GC_FROM_SELF = 13u;
public static const uint GC_STATEMENT_END = 14u;
public static const uint GC_ARM_END = 15u;
public static const uint GC_STATE_YIELD = 16u;
public static const uint GC_DATA_FIRST = 17u;
public static const uint GC_DATA_NEXT = 18u;
public static const uint GC_DATA_CLOSE = 19u;
public static const uint GC_STATE_OPEN = 20u;
public static const uint GC_BLOCK_OPEN = 21u;
public static const uint GC_FROM_DATA = 22u;
public static const uint GC_BLOCK_CLOSE = 23u;
public static const uint GC_DONE_STATE = 24u;
public static const uint GC_DONE_ARM = 25u;
public static const uint GC_FN = 26u;
public static const uint GC_LPAREN = 27u;
public static const uint GC_COMMA = 28u;
public static const uint GC_RETURNS = 29u;
public static const uint GC_RETURN = 30u;
public static const uint GC_START_CALL = 31u;
public static const uint GC_FN_END = 32u;
public static const uint GC_IMPL = 33u;
public static const uint GC_IMPL_OPEN = 34u;
public static const uint GC_NEXT = 35u;
public static const uint GC_NEXT_BODY = 36u;
public static const uint GC_NEXT_END = 37u;
public static const uint GC_GOTO_YIELD = 38u;
public static const uint GC_SOME_AFTER_DATA = 39u;
public static const uint GC_SOME = 40u;
public static const uint GC_RPAREN = 41u;
public static const uint GC_GOTO_DONE = 42u;

// The pieces a token stands for in a copy of a generator's body. `yield`:
// the text before it, `goto Yield`, the state's number, two per local in
// scope, and the start of the output. The `;` of a yield and `return`: the
// text before it and one string.
public static const uint YIELD_PIECES = 4u;
public static const uint YIELD_END_PIECES = 2u;
public static const uint RETURN_PIECES = 2u;

// Error codes. The status word holds the least `token << 5 | code`.
public static const uint GE_OUTSIDE = 1u;
public static const uint GE_PLACE = 2u;
public static const uint GE_LET_TYPE = 3u;
public static const uint GE_LET_TWICE = 4u;
public static const uint GE_LOOP_EXIT = 5u;
public static const uint GE_RETURN_VALUE = 6u;
public static const uint GE_NO_TYPE = 7u;
public static const uint GE_PARAM_ASSIGN = 8u;
public static const uint GE_IMPORT = 9u;
public static const uint GE_SIGNATURE = 10u;

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

public uint token_end(StructuredBuffer<uint> tokens, uint token)
{
    return tokens[token * 3u + 1u] + tokens[token * 3u + 2u];
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

// Where a token is: the generator whose body holds it. `scan1` holds the
// inclusive prefix sums of generators, yields, loop depth and the depth in
// the blocks of a generator's body, `while` and `if`.
public struct GenPlace
{
    public uint gen;
    public uint open;
    public uint close;
    public bool inside;
};

public GenPlace gen_place(StructuredBuffer<uint> records, StructuredBuffer<uint4> scan1, StructuredBuffer<uint> gens,
                          uint token)
{
    GenPlace place;
    place.gen = GN_NONE;
    place.open = 0u;
    place.close = 0u;
    place.inside = false;
    uint ordinal = scan1[token].x;
    if (ordinal == 0u)
        return place;
    uint gen = gens[ordinal - 1u];
    uint open = records[gen * GR_WORDS + GR_OPEN];
    uint end = records[gen * GR_WORDS + GR_END];
    place.gen = gen;
    place.open = open;
    place.close = end - 1u;
    place.inside = open != 0u && token > open && token + 1u < end;
    return place;
}

// Reports a broken rule at `token`. The status word keeps the least key. In
// the run that explains the error the host read, the thread that found it
// writes the spans the message names: the token and token `a`.
public void generator_error(RWStructuredBuffer<uint> status, RWStructuredBuffer<uint> detail,
                            StructuredBuffer<uint> tokens, uint explain_key, uint token, uint code, uint a)
{
    uint key = (token << 5u) | code;
    if (explain_key == key)
    {
        detail[0u] = token_start(tokens, token);
        detail[1u] = token_len(tokens, token);
        detail[2u] = token_start(tokens, a);
        detail[3u] = token_len(tokens, a);
    }
    uint prior;
    InterlockedMin(status[0u], key, prior);
}
