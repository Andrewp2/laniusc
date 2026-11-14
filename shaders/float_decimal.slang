// Exact decimal-to-binary32/binary64 conversion using u32 arithmetic only.
// The Eisel-Lemire fast path follows Rust core::num::dec2flt's lemire.rs;
// Simple Decimal Conversion, the exact fallback, is adapted from its
// decimal_seq.rs and slow.rs; see third_party/rust-dec2flt/NOTICE.md.
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The caller provides a disjoint 768-word STORAGE BUFFER region for each
// active conversion. There is deliberately no private 768-element array.
// Dispatch this exact path over compacted float jobs in bounded batches.
import integer_words;
import primitive_types;
import float_decimal_tables;
import float_decimal_pow5;

public static const uint FLOAT_DECIMAL_WORKSPACE_WORDS = 768u;
public static const uint FLOAT_DECIMAL_OK = 0u;
public static const uint FLOAT_DECIMAL_INVALID_SYNTAX = 1u;
public static const uint FLOAT_DECIMAL_OVERFLOW = 2u;
public static const uint FLOAT_DECIMAL_INVALID_SCALAR = 3u;
public static const uint FLOAT_DECIMAL_INVALID_SPAN = 4u;
public static const uint FLOAT_DECIMAL_INVALID_WORKSPACE = 5u;
public static const uint FLOAT_DECIMAL_INTERNAL_ERROR = 6u;

struct FloatDecimalState
{
    uint count;
    int point;
    bool truncated;
};

uint float_decimal_byte(ByteAddressBuffer source, uint position)
{
    return (source.Load(position & ~3u) >> ((position & 3u) * 8u)) & 255u;
}

bool float_decimal_is_digit(uint value) { return value >= 48u && value <= 57u; }

void float_decimal_trim(inout FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base)
{
    while (state.count != 0u && workspace[base + state.count - 1u] == 0u)
        state.count -= 1u;
}

// Add a signed exponent to the signed difference integer_digits-leading_zeros.
// Cancellation happens BEFORE saturation, so huge mantissas such as a one
// followed by a million zeros and e-1000000 retain their actual value.
int float_decimal_point(uint integer_digits, uint leading_zeros,
    uint2 exponent, bool exponent_negative)
{
    bool negative = integer_digits < leading_zeros;
    uint2 magnitude = uint2(negative ? leading_zeros - integer_digits
        : integer_digits - leading_zeros, 0u);
    if (negative == exponent_negative)
        magnitude = integer_words_add(magnitude, exponent);
    else if (integer_words_less(magnitude, exponent))
    {
        magnitude = integer_words_sub(exponent, magnitude);
        negative = exponent_negative;
    }
    else magnitude = integer_words_sub(magnitude, exponent);
    uint bounded = magnitude.y != 0u ? 4096u : min(magnitude.x, 4096u);
    return negative ? -int(bounded) : int(bounded);
}

bool float_decimal_scan(ByteAddressBuffer source, uint start, uint length,
    RWStructuredBuffer<uint> workspace, uint base, out FloatDecimalState state)
{
    state.count = 0u;
    state.point = 0;
    state.truncated = false;
    uint integer_digits = 0u;
    uint leading_zeros = 0u;
    uint significant_digits = 0u;
    uint last_nonzero = 0u;
    uint2 exponent = uint2(0u, 0u);
    // This exceeds the largest possible source digit count by 4097. Larger
    // exponents cannot cancel back into binary32/binary64 range, even for a
    // maximum-u32 source span. Saturate here, never by wrapping multiplication.
    uint2 exponent_limit = uint2(4096u, 1u);
    bool dot = false;
    bool exp = false;
    bool exponent_negative = false;
    bool exponent_sign_allowed = false;
    bool mantissa_digit = false;
    bool exponent_digit = false;
    bool previous_digit = false;
    bool valid = length != 0u;
    for (uint i = 0u; i < length; i += 1u)
    {
        uint ch = float_decimal_byte(source, start + i);
        if (float_decimal_is_digit(ch))
        {
            uint digit = ch - 48u;
            previous_digit = true;
            if (exp)
            {
                exponent_digit = true;
                exponent_sign_allowed = false;
                if (integer_words_less(exponent, exponent_limit))
                {
                    exponent = integer_words_add(
                        integer_words_multiply(exponent, uint2(10u, 0u)),
                        uint2(digit, 0u));
                    if (integer_words_less(exponent_limit, exponent))
                        exponent = exponent_limit;
                }
            }
            else
            {
                mantissa_digit = true;
                if (!dot) integer_digits += 1u;
                if (significant_digits == 0u && digit == 0u)
                    leading_zeros += 1u;
                else
                {
                    if (significant_digits < FLOAT_DECIMAL_WORKSPACE_WORDS)
                        workspace[base + significant_digits] = digit;
                    significant_digits += 1u;
                    if (digit != 0u) last_nonzero = significant_digits;
                }
            }
            continue;
        }
        if (ch == 95u)
        {
            bool next_digit = i + 1u < length &&
                float_decimal_is_digit(float_decimal_byte(source, start + i + 1u));
            valid = valid && previous_digit && next_digit;
            previous_digit = false;
            exponent_sign_allowed = false;
            continue;
        }
        if (ch == 46u)
        {
            valid = valid && !dot && !exp;
            dot = true;
            previous_digit = false;
            continue;
        }
        if (ch == 101u || ch == 69u)
        {
            valid = valid && !exp && mantissa_digit;
            exp = true;
            exponent_sign_allowed = true;
            previous_digit = false;
            continue;
        }
        if (ch == 43u || ch == 45u)
        {
            valid = valid && exp && exponent_sign_allowed;
            exponent_negative = ch == 45u;
            exponent_sign_allowed = false;
            previous_digit = false;
            continue;
        }
        // Complete the scan even after malformed input. In particular a
        // valid prefix followed by junk can never become a successful value.
        valid = false;
        previous_digit = false;
        exponent_sign_allowed = false;
    }
    if (!valid || !mantissa_digit || (exp && !exponent_digit)) return false;
    state.count = min(last_nonzero, FLOAT_DECIMAL_WORKSPACE_WORDS);
    state.truncated = last_nonzero > FLOAT_DECIMAL_WORKSPACE_WORDS;
    state.point = state.count == 0u ? 0 : float_decimal_point(
        integer_digits, leading_zeros, exponent, exponent_negative);
    return true;
}

uint float_decimal_growth(FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, uint shift)
{
    uint packed = FLOAT_DECIMAL_LEFT_SHIFT_TABLE[shift];
    uint growth = packed >> 11u;
    uint first = packed & 0x7ffu;
    uint end = FLOAT_DECIMAL_LEFT_SHIFT_TABLE[shift + 1u] & 0x7ffu;
    for (uint i = 0u; i < end - first; i += 1u)
    {
        if (i >= state.count) return growth - 1u;
        uint digit = workspace[base + i];
        uint threshold = FLOAT_DECIMAL_LEFT_SHIFT_POW5[first + i];
        if (digit < threshold) return growth - 1u;
        if (digit > threshold) return growth;
    }
    return growth;
}

// Canonical SDC uses <=60-bit shifts with u64 accumulators. Chunking into
// <=28-bit shifts is exact and bounds digit*2^shift+carry below 10*2^28,
// hence below 2^32. The published digit-growth table keeps in-place writes
// from overwriting unread input; truncation records a nonzero tail only.
bool float_decimal_left_shift(inout FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, uint shift)
{
    if (shift == 0u || state.count == 0u) return true;
    if (shift > 28u || state.count > FLOAT_DECIMAL_WORKSPACE_WORDS) return false;
    uint growth = float_decimal_growth(state, workspace, base, shift);
    uint read_index = state.count;
    uint write_index = state.count + growth;
    uint accumulator = 0u;
    while (read_index != 0u)
    {
        read_index -= 1u;
        if (write_index == 0u) return false;
        write_index -= 1u;
        accumulator += workspace[base + read_index] << shift;
        uint quotient = accumulator / 10u;
        uint remainder = accumulator - 10u * quotient;
        if (write_index < FLOAT_DECIMAL_WORKSPACE_WORDS)
            workspace[base + write_index] = remainder;
        else if (remainder != 0u) state.truncated = true;
        accumulator = quotient;
    }
    while (accumulator != 0u)
    {
        if (write_index == 0u) return false;
        write_index -= 1u;
        uint quotient = accumulator / 10u;
        uint remainder = accumulator - 10u * quotient;
        if (write_index < FLOAT_DECIMAL_WORKSPACE_WORDS)
            workspace[base + write_index] = remainder;
        else if (remainder != 0u) state.truncated = true;
        accumulator = quotient;
    }
    if (write_index != 0u) return false;
    state.count = min(state.count + growth, FLOAT_DECIMAL_WORKSPACE_WORDS);
    state.point += int(growth);
    float_decimal_trim(state, workspace, base);
    return true;
}

bool float_decimal_right_shift(inout FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, uint shift)
{
    if (shift == 0u || state.count == 0u) return true;
    if (shift > 28u || state.count > FLOAT_DECIMAL_WORKSPACE_WORDS) return false;
    uint read_index = 0u;
    uint write_index = 0u;
    uint accumulator = 0u;
    while ((accumulator >> shift) == 0u)
    {
        if (read_index < state.count)
        {
            accumulator = 10u * accumulator + workspace[base + read_index];
            read_index += 1u;
        }
        else if (accumulator == 0u) return true;
        else
        {
            while ((accumulator >> shift) == 0u)
            {
                accumulator *= 10u;
                read_index += 1u;
            }
            break;
        }
    }
    state.point -= int(read_index) - 1;
    if (state.point < -2047)
    {
        state.count = 0u;
        state.point = 0;
        state.truncated = false;
        return true;
    }
    uint mask = (1u << shift) - 1u;
    while (read_index < state.count)
    {
        uint digit = accumulator >> shift;
        accumulator = 10u * (accumulator & mask) + workspace[base + read_index];
        read_index += 1u;
        workspace[base + write_index] = digit;
        write_index += 1u;
    }
    while (accumulator != 0u)
    {
        uint digit = accumulator >> shift;
        accumulator = 10u * (accumulator & mask);
        if (write_index < FLOAT_DECIMAL_WORKSPACE_WORDS)
        {
            workspace[base + write_index] = digit;
            write_index += 1u;
        }
        else if (digit != 0u) state.truncated = true;
    }
    state.count = write_index;
    float_decimal_trim(state, workspace, base);
    return true;
}

uint float_decimal_normalizing_shift(uint places)
{
    static const uint POWERS[9] = {0u, 3u, 6u, 9u, 13u, 16u, 19u, 23u, 26u};
    return places < 9u ? POWERS[places] : 28u;
}

bool float_decimal_round(FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, out uint2 value)
{
    value = uint2(0u, 0u);
    if (state.count == 0u || state.point < 0) return true;
    // After normalization the result has <=53 significant binary bits, hence
    // fewer than 19 decimal integer digits. Treat violation as internal error.
    if (state.point >= 19) return false;
    uint point = uint(state.point);
    for (uint i = 0u; i < point; i += 1u)
        value = integer_words_add(integer_words_multiply(value, uint2(10u, 0u)),
            uint2(i < state.count ? workspace[base + i] : 0u, 0u));
    if (point < state.count)
    {
        uint next = workspace[base + point];
        bool up = next >= 5u;
        if (next == 5u && point + 1u == state.count)
            up = state.truncated || (value.x & 1u) != 0u;
        if (up) value = integer_words_add(value, uint2(1u, 0u));
    }
    return true;
}

// 32 x 32 -> 64-bit product as (low32, high32).
uint2 float_decimal_multiply32(uint a, uint b)
{
    uint a0 = a & 0xffffu;
    uint a1 = a >> 16u;
    uint b0 = b & 0xffffu;
    uint b1 = b >> 16u;
    uint p00 = a0 * b0;
    uint p01 = a0 * b1;
    uint p10 = a1 * b0;
    uint middle = (p00 >> 16u) + (p01 & 0xffffu) + (p10 & 0xffffu);
    return uint2((p00 & 0xffffu) | (middle << 16u),
        a1 * b1 + (p01 >> 16u) + (p10 >> 16u) + (middle >> 16u));
}

// 64 x 64 -> 128-bit product as its low and high 64 bits.
void float_decimal_multiply64(uint2 a, uint2 b, out uint2 low, out uint2 high)
{
    uint2 ll = float_decimal_multiply32(a.x, b.x);
    uint2 lh = float_decimal_multiply32(a.x, b.y);
    uint2 hl = float_decimal_multiply32(a.y, b.x);
    uint2 hh = float_decimal_multiply32(a.y, b.y);
    uint word1 = ll.y + lh.x;
    uint carry1 = uint(word1 < lh.x);
    word1 += hl.x;
    carry1 += uint(word1 < hl.x);
    uint word2 = hh.x + lh.y;
    uint carry2 = uint(word2 < lh.y);
    word2 += hl.y;
    carry2 += uint(word2 < hl.y);
    word2 += carry1;
    carry2 += uint(word2 < carry1);
    low = uint2(ll.x, word1);
    high = uint2(word2, hh.y + carry2);
}

// An Eisel-Lemire result: the biased binary exponent and the fraction bits
// (with the hidden bit for the smallest normal reached by rounding a
// subnormal up, which OR-ing the exponent absorbs). power2 -1: undecided.
struct FloatDecimalLemire
{
    uint2 mantissa;
    int power2;
};

// Rust dec2flt lemire::compute_float for w * 10^q; w == 0 gives zero.
// Every decided result is the correctly rounded value; power2 -1 asks for
// the exact path.
FloatDecimalLemire float_decimal_lemire(int q, uint2 w, uint scalar)
{
    bool f32 = scalar == SCALAR_F32;
    uint fraction_bits = f32 ? 23u : 52u;
    int minimum_exponent = f32 ? -127 : -1023;
    int infinite_power = f32 ? 255 : 2047;
    FloatDecimalLemire result;
    result.mantissa = uint2(0u, 0u);
    result.power2 = 0;
    if (integer_words_zero(w) || q < (f32 ? -65 : -342)) return result;
    if (q > (f32 ? 38 : 308))
    {
        result.power2 = infinite_power;
        return result;
    }
    uint lz = w.y != 0u ? 31u - firstbithigh(w.y) : 63u - firstbithigh(w.x);
    w = integer_words_shift_left(w, lz);
    uint index = uint(q + int(FLOAT_DECIMAL_POW5_MIN)) * 4u;
    uint2 high5 = uint2(FLOAT_DECIMAL_POW5[index], FLOAT_DECIMAL_POW5[index + 1u]);
    uint2 low5 = uint2(FLOAT_DECIMAL_POW5[index + 2u], FLOAT_DECIMAL_POW5[index + 3u]);
    uint2 low;
    uint2 high;
    float_decimal_multiply64(w, high5, low, high);
    // Keep fraction bits + hidden bit + rounding bit + a possible leading
    // zero; only all-ones below them needs the lower half of 5^q.
    uint2 mask = integer_words_mask(64u - (fraction_bits + 3u));
    if (all((high & mask) == mask))
    {
        uint2 ignored;
        uint2 second_high;
        float_decimal_multiply64(w, low5, ignored, second_high);
        low = integer_words_add(low, second_high);
        if (integer_words_less(low, second_high))
            high = integer_words_add(high, uint2(1u, 0u));
    }
    // The 128-bit approximation may be one short of a carry into the
    // rounding bit; outside these exponents that cannot be ruled out.
    if (all(low == uint2(0xffffffffu, 0xffffffffu)) && (q < -27 || q > 55))
    {
        result.power2 = -1;
        return result;
    }
    uint upperbit = high.y >> 31u;
    uint shift = upperbit + 64u - fraction_bits - 3u;
    uint2 mantissa = integer_words_shift_right(high, shift);
    int power2 = (((q * (152170 + 65536)) >> 16) + 63) + int(upperbit) - int(lz) -
        minimum_exponent;
    uint2 hidden = integer_words_shift_left(uint2(1u, 0u), fraction_bits);
    if (power2 <= 0)
    {
        if (-power2 + 1 >= 64) return result;
        mantissa = integer_words_shift_right(mantissa, uint(-power2 + 1));
        mantissa = integer_words_add(mantissa, uint2(mantissa.x & 1u, 0u));
        mantissa = integer_words_shift_right(mantissa, 1u);
        result.mantissa = mantissa;
        result.power2 = integer_words_less(mantissa, hidden) ? 0 : 1;
        return result;
    }
    // An exact tie (5^q fits 64 bits, nothing below the rounding bit)
    // rounds to even instead of up.
    if (low.y == 0u && low.x <= 1u && q >= (f32 ? -17 : -4) && q <= (f32 ? 10 : 23) &&
        (mantissa.x & 3u) == 1u &&
        all(integer_words_shift_left(mantissa, shift) == high))
        mantissa.x &= ~1u;
    mantissa = integer_words_add(mantissa, uint2(mantissa.x & 1u, 0u));
    mantissa = integer_words_shift_right(mantissa, 1u);
    if (!integer_words_less(mantissa, integer_words_shift_left(hidden, 1u)))
    {
        mantissa = hidden;
        power2 += 1;
    }
    mantissa &= ~hidden;
    if (power2 >= infinite_power)
    {
        result.power2 = infinite_power;
        return result;
    }
    result.mantissa = mantissa;
    result.power2 = power2;
    return result;
}

// Converts with Eisel-Lemire from the first 19 significant digits, as Rust
// dec2flt does before its exact fallback. With more digits the value lies
// in [w, w + 1) * 10^q, so a result both ends agree on is the rounded value.
// Returns false when the exact path must decide.
bool float_decimal_lemire_bits(FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, uint scalar,
    out uint2 bits, out uint status)
{
    bits = uint2(0u, 0u);
    status = FLOAT_DECIMAL_OK;
    uint digits = min(state.count, 19u);
    uint2 w = uint2(0u, 0u);
    for (uint i = 0u; i < digits; i += 1u)
        w = integer_words_add(integer_words_multiply(w, uint2(10u, 0u)),
            uint2(workspace[base + i], 0u));
    int q = state.point - int(digits);
    FloatDecimalLemire value = float_decimal_lemire(q, w, scalar);
    if (value.power2 < 0) return false;
    if (state.count > 19u || state.truncated)
    {
        FloatDecimalLemire above = float_decimal_lemire(q,
            integer_words_add(w, uint2(1u, 0u)), scalar);
        if (above.power2 != value.power2 || any(above.mantissa != value.mantissa))
            return false;
    }
    if (value.power2 == (scalar == SCALAR_F32 ? 255 : 2047))
    {
        status = FLOAT_DECIMAL_OVERFLOW;
        return true;
    }
    bits = scalar == SCALAR_F32
        ? uint2(value.mantissa.x | (uint(value.power2) << 23u), 0u)
        : uint2(value.mantissa.x, value.mantissa.y | (uint(value.power2) << 20u));
    return true;
}

uint float_decimal_convert(inout FloatDecimalState state,
    RWStructuredBuffer<uint> workspace, uint base, uint scalar, out uint2 bits)
{
    bits = uint2(0u, 0u);
    // A nonzero value with decimal point p is in [10^(p-1), 10^p).
    // For f32, values below 1e-46 round to zero and values at least 1e39
    // overflow. Keep the adjacent decades on the exact rounding path.
    int minimum_point = scalar == SCALAR_F32 ? -45 : -324;
    int overflow_point = scalar == SCALAR_F32 ? 40 : 310;
    if (state.count == 0u || state.point < minimum_point) return FLOAT_DECIMAL_OK;
    if (state.point >= overflow_point) return FLOAT_DECIMAL_OVERFLOW;
    // Eisel-Lemire decides almost every literal with two 64-bit products;
    // the decimal shifts below cost up to hundreds of digit passes and run
    // only when it cannot.
    uint fast_status;
    if (float_decimal_lemire_bits(state, workspace, base, scalar, bits, fast_status))
        return fast_status;
    uint fraction_bits = scalar == SCALAR_F32 ? 23u : 52u;
    int minimum_exponent = scalar == SCALAR_F32 ? -126 : -1022;
    int infinite_power = scalar == SCALAR_F32 ? 255 : 2047;
    int exponent2 = 0;
    uint steps = 0u;
    // Normalize the decimal into [1/2, 1]. The iteration guards diagnose
    // broken helper invariants; supported decimal exponents need far fewer
    // than 1024 shifts. They do not truncate a source-token scan.
    while (state.point > 0)
    {
        if (steps++ >= 1024u) return FLOAT_DECIMAL_INTERNAL_ERROR;
        uint shift = float_decimal_normalizing_shift(uint(state.point));
        if (!float_decimal_right_shift(state, workspace, base, shift))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        exponent2 += int(shift);
    }
    while (state.point <= 0)
    {
        if (state.count == 0u) return FLOAT_DECIMAL_OK;
        uint shift;
        if (state.point == 0)
        {
            uint first = workspace[base];
            if (first >= 5u) break;
            shift = first <= 1u ? 2u : 1u;
        }
        else shift = float_decimal_normalizing_shift(uint(-state.point));
        if (steps++ >= 1024u) return FLOAT_DECIMAL_INTERNAL_ERROR;
        if (!float_decimal_left_shift(state, workspace, base, shift))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        exponent2 -= int(shift);
    }
    exponent2 -= 1;
    while (minimum_exponent > exponent2)
    {
        if (steps++ >= 1024u) return FLOAT_DECIMAL_INTERNAL_ERROR;
        uint shift = min(uint(minimum_exponent - exponent2), 28u);
        if (!float_decimal_right_shift(state, workspace, base, shift))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        exponent2 += int(shift);
    }
    if (exponent2 - minimum_exponent + 1 >= infinite_power)
        return FLOAT_DECIMAL_OVERFLOW;
    uint remaining = fraction_bits + 1u;
    while (remaining != 0u)
    {
        uint shift = min(remaining, 28u);
        if (!float_decimal_left_shift(state, workspace, base, shift))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        remaining -= shift;
    }
    uint2 mantissa;
    if (!float_decimal_round(state, workspace, base, mantissa))
        return FLOAT_DECIMAL_INTERNAL_ERROR;
    uint2 carry = integer_words_shift_left(uint2(1u, 0u), fraction_bits + 1u);
    if (!integer_words_less(mantissa, carry))
    {
        if (!float_decimal_right_shift(state, workspace, base, 1u))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        exponent2 += 1;
        if (!float_decimal_round(state, workspace, base, mantissa))
            return FLOAT_DECIMAL_INTERNAL_ERROR;
        if (exponent2 - minimum_exponent + 1 >= infinite_power)
            return FLOAT_DECIMAL_OVERFLOW;
    }
    int power2 = exponent2 - minimum_exponent + 1;
    uint2 hidden = integer_words_shift_left(uint2(1u, 0u), fraction_bits);
    if (integer_words_less(mantissa, hidden)) power2 -= 1;
    if (power2 < 0 || power2 >= infinite_power)
        return FLOAT_DECIMAL_INTERNAL_ERROR;
    if (scalar == SCALAR_F32)
        bits = uint2((mantissa.x & 0x007fffffu) | (uint(power2) << 23u), 0u);
    else bits = uint2(mantissa.x,
        (mantissa.y & 0x000fffffu) | (uint(power2) << 20u));
    return FLOAT_DECIMAL_OK;
}

// Parse an unsigned decimal token. Its unary sign is supplied separately.
// Separators are accepted only between digits. At least one mantissa digit
// is required; a decimal point and exponent are individually optional.
// OK preserves signed zero/subnormals. Finite overflow is a distinct error.
// bits is zero on every error. consumed is the entire token length for a
// syntactically scanned span (including errors); argument errors consume 0.
public uint float_decimal_parse_bits(ByteAddressBuffer source_bytes,
    uint source_len, uint token_start, uint token_len, uint scalar, bool negative,
    RWStructuredBuffer<uint> workspace, uint workspace_base,
    out uint2 bits, out uint consumed)
{
    bits = uint2(0u, 0u);
    consumed = 0u;
    if (scalar != SCALAR_F32 && scalar != SCALAR_F64)
        return FLOAT_DECIMAL_INVALID_SCALAR;
    uint source_capacity;
    source_bytes.GetDimensions(source_capacity);
    if ((source_capacity & 3u) != 0u || source_len > source_capacity ||
        token_start > source_len || token_len > source_len - token_start)
        return FLOAT_DECIMAL_INVALID_SPAN;
    uint workspace_capacity; uint workspace_stride;
    workspace.GetDimensions(workspace_capacity, workspace_stride);
    if (workspace_base > workspace_capacity ||
        FLOAT_DECIMAL_WORKSPACE_WORDS > workspace_capacity - workspace_base)
        return FLOAT_DECIMAL_INVALID_WORKSPACE;
    FloatDecimalState state;
    bool valid = float_decimal_scan(source_bytes, token_start, token_len,
        workspace, workspace_base, state);
    consumed = token_len;
    if (!valid) return FLOAT_DECIMAL_INVALID_SYNTAX;
    uint status = float_decimal_convert(state, workspace, workspace_base, scalar, bits);
    if (status != FLOAT_DECIMAL_OK)
    {
        bits = uint2(0u, 0u);
        return status;
    }
    if (negative)
    {
        if (scalar == SCALAR_F32) bits.x |= 0x80000000u;
        else bits.y |= 0x80000000u;
    }
    return FLOAT_DECIMAL_OK;
}
