// Shared layout of the desugaring after the lexer's token build
// (crates/laniusc-compiler/src/compiler/desugar.rs mirrors it).
//
// The desugaring runs in rounds, one per feature: closures, generators,
// machines. Each round reads the token stream the round before it left and
// writes the next one. A round's own kernels read the stream into records,
// check the feature's rules and write pieces: copies of token ranges and
// generated words. The shared kernels expand the pieces, place their text in
// a region of the lexer's byte buffer after the source, build its tokens and
// splice them into the stream.
//
// Every round has its own slice of `sizes` (the counts of the run), `args`
// (indirect dispatch sizes) and `blocks` (kernel parameters, one 256-byte
// uniform block each). The plan kernel writes all three from counts on the
// GPU, so the host records every dispatch before it knows a count. A round
// whose feature the pack does not use gets zero workgroups everywhere.
module desugaring_layout;

import shared.syntax.generated_token_ids;
import shared.buffers.byte_packing;

public static const uint DS_NONE = 0xffffffffu;

// Sizes, per round.
public static const uint S_TOKENS = 0u;      // tokens the round reads; 0 when it does nothing
public static const uint S_LIVE = 1u;        // tokens while the round's expansion goes on, else 0
public static const uint S_F0 = 2u;          // counts of the feature's own kernels
public static const uint S_F1 = 3u;
public static const uint S_F2 = 4u;
public static const uint S_F3 = 5u;
public static const uint S_FPIECES = 6u;     // pieces the feature wrote
public static const uint S_PIECES = 7u;      // pieces after the expansion of token ranges
public static const uint S_REGION = 8u;      // bytes of generated text
public static const uint S_GENERATED = 9u;   // generated tokens
public static const uint S_OUT = 10u;        // tokens after the splice
public static const uint S_REGION_BASE = 11u; // first byte of the round's text in `in_bytes`
public static const uint S_REGION_CAP = 12u;  // bytes the round's text may take
public static const uint S_SPLICED = 13u;    // tokens the splice reads; 0 when nothing is spliced
public static const uint S_ANCHOR_BASE = 14u; // the round's first row of `anchors`
// What a run that did not fit needed; the host sizes the next run from them.
public static const uint S_NEED_TOKENS = 15u;
public static const uint S_NEED_PIECES = 16u;
public static const uint S_NEED_REGION = 17u;
public static const uint S_NEED_OUT = 18u;
public static const uint SIZE_WORDS = 64u;

// Indirect dispatches, three words each, per round. The shared stages use
// the first ones, a feature's kernels the ones from A_FEATURE.
public static const uint A_EXPAND_SCAN = 0u;
public static const uint A_EXPAND_SCAN_ONE = 1u;
public static const uint A_PIECES = 2u;
public static const uint A_PIECE_SCAN = 3u;
public static const uint A_PIECE_SCAN_ONE = 4u;
public static const uint A_REGION_WORDS = 5u;
public static const uint A_REGION_BYTES = 6u;
public static const uint A_REGION_SCAN = 7u;
public static const uint A_REGION_SCAN_ONE = 8u;
public static const uint A_SPLICE = 9u;      // the round's tokens and the end of the stream
public static const uint A_SPLICE_SCAN = 10u;
public static const uint A_SPLICE_SCAN_ONE = 11u;
public static const uint A_GENERATED = 12u;
public static const uint A_KEPT = 13u;
public static const uint A_OUT = 14u;
public static const uint A_FEATURE = 16u;
public static const uint ARG_TRIPLES = 64u;  // 768 bytes, a multiple of 256

// Parameter blocks, 64 words apart (the uniform offset alignment), per
// round. The shared stages use the first ones.
public static const uint BLOCK_WORDS = 64u;
public static const uint P_EXPAND_SCAN_0 = 0u; // desugar/closures/scan_four_word_rows: (count, mode, tiles)
public static const uint P_EXPAND_SCAN_1 = 1u;
public static const uint P_EXPAND_SCAN_2 = 2u;
public static const uint P_PIECE_SCAN_0 = 3u;
public static const uint P_PIECE_SCAN_1 = 4u;
public static const uint P_PIECE_SCAN_2 = 5u;
public static const uint P_REGION_SCAN_0 = 6u;
public static const uint P_REGION_SCAN_1 = 7u;
public static const uint P_REGION_SCAN_2 = 8u;
public static const uint P_SPLICE_SCAN_0 = 9u;
public static const uint P_SPLICE_SCAN_1 = 10u;
public static const uint P_SPLICE_SCAN_2 = 11u;
public static const uint P_FEATURE = 16u;
public static const uint BLOCKS = 48u;

// Bits of the lexer's feature word the host reads with the token count.
public static const uint FEATURE_MACHINES = 0x00001000u;
public static const uint FEATURE_GENERATORS = 0x00002000u;
public static const uint FEATURE_CLOSURES = 0x00004000u;
public static const uint DESUGAR_RESERVED = 0x20000000u;
public static const uint DESUGAR_REGION_OVERFLOW = 0x40000000u;
public static const uint DESUGAR_RULE_ERROR = 0x80000000u;
public static const uint DESUGAR_STOPS = DESUGAR_RESERVED | DESUGAR_REGION_OVERFLOW | DESUGAR_RULE_ERROR;

public static const uint DESUGAR_NO_ERROR = 0xffffffffu;

public static const uint DESUGAR_DISPATCH_X_STRIDE = 16776960u;
public static const uint DESUGAR_MAX_GROUPS_X = 65535u;
public static const uint DESUGAR_SCAN_TILE_ROWS = 2048u;
public static const uint DESUGAR_SPLICE_TILE_ROWS = 256u;

// The lower bound of an owner in the ordered generated stream.
public uint first_owner_at_least(StructuredBuffer<uint> owners, uint lo, uint hi, uint owner)
{
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (owners[mid] < owner)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

// Piece kinds. A piece row is `(count, kind, value, anchor)` as a feature
// writes it and `(length, kind, value, anchor)` after the expansion. Its
// owner is the token of the round's stream it goes before.
//   RANGE: `count` tokens of the stream from token `value`. The expansion
//   turns it into one COPY piece per token, the first COPY_FIRST.
//   CONST: constant string `value` of the feature's table.
//   NUMBER: the decimal digits of `value`; ID: ten digits of it.
//   SNAKE: the snake_case form of token `anchor`; CAMEL its CamelCase form,
//   CAMEL_SNAKE the snake_case form of that.
// Generated words join as the lexer would join them: two bytes of different
// pieces join when both are name characters, as `__lanius_in_` and `Idle`
// make `__lanius_in_Idle`. Two tokens of one range never join.
public static const uint PIECE_RANGE = 0u;
public static const uint PIECE_CONST = 1u;
public static const uint PIECE_NUMBER = 2u;
public static const uint PIECE_SNAKE = 3u;
public static const uint PIECE_CAMEL = 4u;
public static const uint PIECE_CAMEL_SNAKE = 5u;
public static const uint PIECE_ID = 6u;
public static const uint PIECE_COPY_FIRST = 7u;
public static const uint PIECE_COPY_NEXT = 8u;
public static const uint ID_DIGITS = 10u;
// No well-formed program reaches it. It bounds the loops over a name.
public static const uint DS_MAX_NAME = 65536u;

public struct TokenRow
{
    public uint kind;
    public uint start;
    public uint len;
};

public uint load_byte(ByteAddressBuffer bytes, uint at)
{
    return byte_address_load_u8(bytes, at);
}

// The bytes a name is read from: the lexer's byte buffer, read-only or
// writable.
public interface IByteSource
{
    public uint byte_at(uint at);
}

public bool name_char(uint c)
{
    return (c >= 48u && c <= 57u) || (c >= 65u && c <= 90u) || (c >= 97u && c <= 122u) || c == 95u;
}

public bool upper_char(uint c)
{
    return c >= 65u && c <= 90u;
}

public bool lower_char(uint c)
{
    return c >= 97u && c <= 122u;
}

public bool digit_char(uint c)
{
    return c >= 48u && c <= 57u;
}

// A word boundary of the snake_case form: before an upper-case letter that
// follows a lower-case letter or digit, or that starts a capitalized word
// after an acronym.
public bool snake_boundary(uint previous, uint current, uint next)
{
    if (!upper_char(current))
        return false;
    return lower_char(previous) || digit_char(previous) || (upper_char(previous) && lower_char(next));
}

public uint decimal_digits(uint value)
{
    uint count = 1u;
    for (uint rest = value; rest >= 10u; rest /= 10u)
        count += 1u;
    return count;
}

// Digit `offset` of the `width` digits of `value`, most significant first.
public uint decimal_digit(uint value, uint width, uint offset)
{
    uint divisor = 1u;
    for (uint digit = offset + 1u; digit < width && digit < 10u; digit += 1u)
        divisor *= 10u;
    return 48u + (value / divisor) % 10u;
}

// The snake_case form of the `len` bytes at `start`: byte `want` of it, or
// its length when `want` is DS_NONE.
public uint snake_text<B : IByteSource>(B bytes, uint start, uint len, uint want)
{
    len = min(len, DS_MAX_NAME);
    uint at = 0u;
    uint previous = 0u;
    for (uint i = 0u; i < len; i += 1u)
    {
        uint current = bytes.byte_at(start + i);
        uint next = i + 1u < len ? bytes.byte_at(start + i + 1u) : 0u;
        if (snake_boundary(previous, current, next))
        {
            if (at == want)
                return 95u;
            at += 1u;
        }
        if (at == want)
            return upper_char(current) ? current + 32u : current;
        at += 1u;
        previous = current;
    }
    return want == DS_NONE ? at : 0u;
}

// The CamelCase form of the `len` bytes at `start`: the parts between `_`
// joined, each with its first letter in upper case. With `snake`, the
// snake_case form of that. Byte `want` of the form, or its length when
// `want` is DS_NONE.
public uint camel_text<B : IByteSource>(B bytes, uint start, uint len, bool snake, uint want)
{
    uint out = 0u;
    uint previous = 0u;
    uint current = 0u;
    bool upper_next = true;
    len = min(len, DS_MAX_NAME);
    for (uint i = 0u; i <= len; i += 1u)
    {
        uint next = 0u;
        if (i < len)
        {
            uint c = bytes.byte_at(start + i);
            if (c == 95u)
            {
                upper_next = true;
                continue;
            }
            next = (upper_next && lower_char(c)) ? c - 32u : c;
            upper_next = false;
        }
        // `current` has its successor now: 0 at the end of the name.
        if (current != 0u)
        {
            if (snake && snake_boundary(previous, current, next))
            {
                if (out == want)
                    return 95u;
                out += 1u;
            }
            if (out == want)
                return (snake && upper_char(current)) ? current + 32u : current;
            out += 1u;
            previous = current;
        }
        current = next;
    }
    return want == DS_NONE ? out : 0u;
}
