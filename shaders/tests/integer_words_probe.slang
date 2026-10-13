// Differential probe of the production integer helpers, using only u32 GPU
// arithmetic. The host oracle uses native Rust integer operations.
import integer_words;
import primitive_types;

struct Params { uint query_count; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
// kind, scalar, left[2], right[2], shift/digit, reserved.
// Decimal-sequence rows use left as (first byte, byte count).
StructuredBuffer<uint> queries;
StructuredBuffer<uint> decimal_bytes;
RWStructuredBuffer<uint> results; // 27 words per query; see the host field names.

void put_words(uint output, uint field, uint2 value)
{
    results[output + field] = value.x;
    results[output + field + 1u] = value.y;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= gParams.query_count) return;
    uint input = row * 8u;
    uint output = row * 27u;
    for (uint field = 0u; field < 27u; field++) results[output + field] = 0u;
    uint kind = queries[input];
    uint scalar = queries[input + 1u];
    uint2 left = uint2(queries[input + 2u], queries[input + 3u]);
    uint2 right = uint2(queries[input + 4u], queries[input + 5u]);
    uint shift = queries[input + 6u];
    if (kind == 1u)
    {
        uint2 value = uint2(0u, 0u);
        bool accepted = true;
        for (uint i = 0u; i < left.y; i++)
        {
            uint2 next;
            if (!integer_words_append_decimal(value, decimal_bytes[left.x + i] - 48u, next))
            {
                accepted = false;
                break;
            }
            value = next;
        }
        results[output] = uint(accepted);
        put_words(output, 1u, accepted ? value : uint2(0u, 0u));
        return;
    }
    if (kind == 2u)
    {
        uint2 next;
        results[output] = uint(integer_words_append_decimal(left, shift, next));
        put_words(output, 1u, next);
        return;
    }
    if (kind == 3u)
    {
        results[output] = uint(integer_words_magnitude_fits(left, scalar, false));
        results[output + 1u] = uint(integer_words_magnitude_fits(left, scalar, true));
        return;
    }
    uint bits = scalar_integer_bits(scalar);
    results[output] = bits;
    results[output + 1u] = uint(scalar_is_signed_integer(scalar));
    // Preserve the original unsigned magnitude for literal admission checks.
    results[output + 23u] = uint(integer_words_magnitude_fits(left, scalar, false));
    results[output + 24u] = uint(integer_words_magnitude_fits(left, scalar, true));
    left = integer_words_normalize(left, bits);
    right = integer_words_normalize(right, bits);
    put_words(output, 2u, integer_words_normalize(integer_words_add(left, right), bits));
    put_words(output, 4u, integer_words_normalize(integer_words_sub(left, right), bits));
    put_words(output, 6u, integer_words_normalize(integer_words_multiply(left, right), bits));
    put_words(output, 8u, integer_words_normalize(integer_words_negate(left), bits));
    put_words(output, 10u, integer_words_normalize(integer_words_shift_left(left, shift), bits));
    put_words(output, 12u, integer_words_shift_right(left, shift));
    put_words(output, 14u, integer_words_arithmetic_shift_right(left, shift, bits));
    uint2 quotient; uint2 remainder;
    results[output + 16u] = integer_words_divide(left, right, scalar, quotient, remainder);
    put_words(output, 17u, quotient);
    put_words(output, 19u, remainder);
    results[output + 21u] = uint(integer_words_less_signed(left, right, bits));
    results[output + 22u] = uint(integer_words_less(left, right));
    put_words(output, 25u, integer_words_sign_extend(left, bits));
}
