// canonical_type_reference_matches without frame storage, for kernels whose
// indirect HIR-sized grids cannot bind the thread scratch table (predicate
// method validation). The walk keeps only the child slot each level took and
// replays that path from the root to resume a parent, as in
// scoped_type_stackless.slang: classification is deterministic over
// read-only tables, and a replay skips constant identities.
//
// INTERIM: the end state (P7) compares canonical type IDs instead.
import constant_value;
import dependency_interface;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_stackless;
import type_checker.dependencies.constant_view;
import type_checker.dependencies.canonical_field_types;
#include "../scoped_type_path.slang"

// As canonical_type_reference_matches. A root that resolves to a leaf is the
// walk's only node, so the leaf comparison and the field walk share one
// scoped equality site.
public bool canonical_type_reference_matches_stackless<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint2 candidate, uint capacity, uint tokens)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint2 root_expected = uint2(5u, type);
    if (!canonical_field_leaf<Graph>(instance, root_expected)) return false;
    bool leaf_root = root_expected.x != 5u;
    if (!leaf_root && candidate.x != 3u) return false;
    // canonical_field_ref_matches(root_expected.y, candidate.y) otherwise.
    uint3 root_pair = uint3(leaf_root ? 0u : root_expected.y, candidate.x, candidate.y);
    SCOPED_TYPE_PATH(path);
    uint depth = 0u;
    uint resume = INVALID;
    uint3 pair = root_pair;
    for (;;)
    {
        uint2 expected = uint2(5u, pair.x);
        uint root = INVALID; bool constant = false;
        if (leaf_root) expected = root_expected;
        else
        {
            root = canonical_field_root(pair.x);
            uint root_kind = root < dependency_type_count() ? dependency_type_word(root * 9u) : 0u;
            constant = root_kind == 8u || root_kind == 9u || root_kind == 10u;
            if (!constant && !canonical_type_field_leaf<Graph>(instance, expected)) return false;
        }
        uint count = 0u;
        // A constant operand or an array length shares one match site.
        bool constant_identity = constant; bool count_identity = false;
        uint constant_type = root; uint2 actual = uint2(0u, INVALID);
        if (constant)
        {
            if (!application_constant_argument(pair.y, pair.z, actual.x, actual.y)) return false;
        }
        else if (expected.x != 5u)
        {
            if (!scoped_type_refs_equal_stackless<Graph>(expected.x, expected.y, INVALID,
                pair.y, pair.z, INVALID, capacity, tokens)) return false;
        }
        else
        {
            pair.x = expected.y;
            if (pair.y != 3u || pair.z >= capacity) return false;
            uint kind = dependency_type_word(pair.x * 9u) - 2u;
            uint actual_kind = Graph.metadata(pair.z, 0u);
            if (kind < 1u || kind > 4u || kind != actual_kind) return false;
            if (kind == 1u)
            {
                if (Graph.metadata(pair.z, 1u) != INVALID ||
                    dependency_type_word(pair.x * 9u + 1u) != Graph.metadata(pair.z, 7u) ||
                    dependency_type_word(pair.x * 9u + 8u) != Graph.metadata(pair.z, 8u) ||
                    dependency_type_word(pair.x * 9u + 2u) != Graph.metadata(pair.z, 9u)) return false;
                count = dependency_type_word(pair.x * 9u + 4u);
                if (count > 32u || count != Graph.metadata(pair.z, 2u)) return false;
            }
            else
            {
                if (kind == 2u)
                {
                    actual = uint2(Graph.metadata(pair.z, 5u), Graph.metadata(pair.z, 6u));
                    constant_type = dependency_array_length_type(pair.x);
                    constant_identity = true; count_identity = true;
                }
                count = 1u;
            }
        }
        if (constant_identity && resume == INVALID && !canonical_constant_matches<Graph>(instance,
            constant_type, actual, tokens, count_identity)) return false;
        uint slot = select(resume == INVALID, 0u, SCOPED_TYPE_PATH_SLOT(path, depth));
        bool resumed = depth == resume;
        slot += uint(resumed);
        resume = select(resumed, INVALID, resume);
        if (slot == count)
        {
            if (depth == 0u) return true;
            resume = depth - 1u; depth = 0u; pair = root_pair;
            continue;
        }
        uint tag; uint payload;
        if (Graph.metadata(pair.z, 0u) == 1u)
        {
            if (!Graph.argument(pair.z, slot, tag, payload)) return false;
        }
        else { tag = Graph.metadata(pair.z, 3u); payload = Graph.metadata(pair.z, 4u); }
        uint child = dependency_type_edge_word(dependency_type_word(pair.x * 9u + 3u) + slot);
        if (depth + 1u == LIMIT) return false;
        SCOPED_TYPE_PATH_SET(path, depth, slot);
        depth++; pair = uint3(child, tag, payload);
    }
}
