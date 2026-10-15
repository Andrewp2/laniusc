import primitive_types;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;
import tests.typed_constant_identity_fixture;

RWStructuredBuffer<uint4> results;

// Original case IDs and 64-lane dispatch are retained across fixture families.
[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint id = dtid.x;
    if (id > 19u) return;
    uint left = 0u; uint right = 1u; uint context = INVALID;
    if (id == 1u) { left = 0u; right = 2u; }
    if (id == 2u) { left = 2u; right = 3u; }
    if (id == 3u) { left = 4u; right = 5u; }
    if (id == 4u) { left = 6u; right = 6u; }
    if (id == 5u) { left = 7u; right = 7u; }
    if (id == 6u) { left = 8u; right = 2u; }
    if (id == 7u) { left = 9u; right = 4u; }
    if (id == 8u) { left = 10u; right = 2u; context = 0u; }
    if (id == 9u) { left = 10u; right = 2u; context = 2u; }
    if (id == 10u) { left = 12u; right = 12u; }
    if (id == 11u) { left = 13u; right = 14u; }
    if (id == 12u) { left = 15u; right = 15u; }
    if (id == 13u) { left = 16u; right = 16u; }
    if (id == 14u) { left = 17u; right = 17u; }
    if (id == 15u) { left = 18u; right = 18u; }
    if (id == 16u) { left = 19u; right = 20u; }
    if (id == 17u) { left = 19u; right = 21u; }
    uint a; uint b;
    bool equal = scoped_type_refs_equal<LeftGraph>(3u, left, context, 3u, right, INVALID, 22u, 64u);
    uint hashes[2]; bool hash_ok[2];
    // Both reads always run, including after a rejected left hash. Preserve
    // declaration scope on the left and caller scope on the right.
    [loop]
    for (uint side = 0u; side < 2u; side++)
        hash_ok[side] = scoped_type_ref_hash<LeftGraph>(3u,
            side == 0u ? left : right, side == 0u ? context : INVALID, 22u, 64u, hashes[side]);
    a = hashes[0u]; b = hashes[1u];
    bool left_ok = hash_ok[0u]; bool right_ok = hash_ok[1u];
    if (id == 18u)
    {
        equal = scoped_type_refs_equal_graphs<LeftGraph, RightGraph>(3u, 0u, INVALID, 3u, 0u, INVALID, 22u, 22u, 64u);
        right_ok = scoped_type_ref_hash<RightGraph>(3u, 0u, INVALID, 22u, 64u, b);
    }
    if (id == 19u)
    {
        bool concrete_equal[3];
        // Keep all three comparisons, in order, through one reader call site.
        [loop]
        for (uint pair = 0u; pair < 3u; pair++)
            concrete_equal[pair] = concrete_type_refs_equal<LeftGraph>(
                3u, pair == 0u ? 8u : pair == 1u ? 4u : 0u,
                3u, pair == 1u ? 5u : 2u, 64u);
        equal = concrete_equal[0u];
        left_ok = concrete_equal[1u];
        right_ok = !concrete_equal[2u];
        results[id] = uint4(equal ? 1u : 0u, left_ok ? 1u : 0u, right_ok ? 1u : 0u, 1u); return;
    }

    results[id] = uint4(equal ? 1u : 0u, left_ok ? 1u : 0u, right_ok ? 1u : 0u, left_ok && right_ok && a == b ? 1u : 0u);
}
