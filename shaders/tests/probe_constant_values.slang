// Execute the production typed-value contract independently of parser/replay.
import constant_value;
struct Params { uint query_count; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> queries;
RWStructuredBuffer<uint> results;

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= gParams.query_count) return;
    uint input = row * 6u;
    uint output = row * 16u;
    uint3 value = uint3(queries[input], queries[input + 1u], queries[input + 2u]);
    uint3 other = uint3(queries[input + 3u], queries[input + 4u], queries[input + 5u]);
    uint count;
    results[output] = uint(constant_value_is_valid(value));
    results[output + 1u] = uint(constant_value_to_count(value, count));
    results[output + 2u] = count;
    uint3 atom;
    results[output + 3u] = uint(constant_value_from_integer_magnitude(value.x, value.yz, false, atom));
    results[output + 4u] = atom.x; results[output + 5u] = atom.y; results[output + 6u] = atom.z;
    results[output + 7u] = uint(constant_value_from_integer_magnitude(value.x, value.yz, true, atom));
    results[output + 8u] = atom.x; results[output + 9u] = atom.y; results[output + 10u] = atom.z;
    results[output + 11u] = uint(constant_values_equal(value, other));
    results[output + 12u] = uint(constant_value_from_count(value.y, value.x, atom));
    results[output + 13u] = atom.x; results[output + 14u] = atom.y; results[output + 15u] = atom.z;
}
