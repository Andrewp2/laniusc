// The scoped type hash and equality walkers without frame storage, for
// kernels whose dispatch cannot bind the thread scratch table (indirect,
// HIR-sized grids). A walk keeps only the child slot it took at each level
// (scoped_type_path.slang, 44 bytes). Completing a node replays the path from
// the root to recover its parent. Classification is deterministic over the
// read-only graph, so a replay revisits the same nodes and passes the same
// checks; it skips constant identities and discards its hash mixes.
//
// The local walkers also reject a child equal to an ancestor. A repeated
// reference re-enters the same deterministic walk and so descends until
// DEPTH_LIMIT: these walkers fail on exactly the same inputs without it.
//
// INTERIM, like the scratch walkers: the end state (P7) replaces these walks
// with canonical type IDs, and the walkers are deleted.
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;
#include "scoped_type_path.slang"

public bool scoped_type_ref_hash_stackless<Graph : IParameterScopedTypeGraph>(
    uint tag, uint payload, uint context, uint type_capacity,
    uint token_capacity, out uint result)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    SCOPED_TYPE_PATH(path);
    uint depth = 0u;
    // While replaying: the depth whose frame resumes, and its hash.
    uint resume = INVALID; uint resume_hash = 0u;
    uint hash = 2166136261u;
    result = 0u;
    uint3 ref = uint3(tag, payload, context);
    for (;;)
    {
        if (ref.x == 2u && ref.z != INVALID)
        {
            if (ref.y >= token_capacity ||
                !Graph.substitute_type_parameter(ref.z, ref.y, ref.x, ref.y) ||
                (ref.x != 1u && ref.x != 2u && ref.x != 3u)) return false;
            ref.z = INVALID;
        }
        if (ref.y == INVALID) return false;
        uint count = 0u;
        hash = scoped_type_hash_mix(hash,
            application_argument_is_constant(ref.x) ? APPLICATION_CONSTANT_ARGUMENT : ref.x);
        bool constant = false; bool count_identity = false;
        uint3 constant_ref = uint3(0u, INVALID, INVALID);
        if (ref.x == 1u)
        {
            if (ref.y == 0u) return false;
            hash = scoped_type_hash_mix(hash, ref.y);
        }
        else if (ref.x == 2u)
        {
            if (ref.y >= token_capacity || !Graph.parameter_is_valid(ref.y, false)) return false;
            hash = scoped_type_hash_mix(hash, ref.y);
        }
        else if (application_argument_is_constant(ref.x))
        {
            constant = true;
            constant_ref = uint3(ref.x & ~APPLICATION_CONSTANT_ARGUMENT, ref.y, ref.z);
        }
        else if (ref.x == 3u && ref.y < type_capacity)
        {
            uint kind = Graph.metadata(ref.y, 0u);
            hash = scoped_type_hash_mix(hash, kind);
            if (kind == 1u)
            {
                uint declaration = Graph.metadata(ref.y, 1u);
                hash = scoped_type_hash_mix(hash, declaration);
                if (declaration == INVALID)
                {
                    for (uint field = 7u; field <= 9u; field++)
                    {
                        uint identity = Graph.metadata(ref.y, field);
                        if (identity == INVALID) return false;
                        hash = scoped_type_hash_mix(hash, identity);
                    }
                }
                else if (declaration >= token_capacity) return false;
                count = Graph.metadata(ref.y, 2u);
                if (count > NOMINAL_APPLICATION_ARGUMENT_LIMIT) return false;
                hash = scoped_type_hash_mix(hash, count);
            }
            else if (kind == 2u || kind == 3u || kind == 4u)
            {
                if (kind == 2u)
                {
                    constant = true; count_identity = true;
                    constant_ref = uint3(Graph.metadata(ref.y, 5u), Graph.metadata(ref.y, 6u), ref.z);
                }
                count = 1u;
            }
            else return false;
        }
        else return false;
        if (constant && resume == INVALID)
        {
            uint identity_hash;
            if (!scoped_constant_ref_or_count_hash<Graph>(constant_ref, token_capacity,
                count_identity, identity_hash)) return false;
            hash = scoped_type_hash_mix(hash, identity_hash);
        }
        // A replay descends through the recorded slots, each below its
        // node's count, then resumes its target after the child that
        // completed.
        uint slot = select(resume == INVALID, 0u, SCOPED_TYPE_PATH_SLOT(path, depth));
        bool resumed = depth == resume;
        slot += uint(resumed);
        hash = select(resumed, resume_hash, hash);
        resume = select(resumed, INVALID, resume);
        if (slot == count)
        {
            hash = scoped_type_hash_mix(hash, INVALID);
            if (depth == 0u) { result = hash; return true; }
            resume = depth - 1u; resume_hash = hash;
            depth = 0u; ref = uint3(tag, payload, context);
            continue;
        }
        uint child_tag; uint child_payload;
        if (Graph.metadata(ref.y, 0u) == 1u)
        {
            if (!Graph.argument(ref.y, slot, child_tag, child_payload)) return false;
        }
        else
        {
            child_tag = Graph.metadata(ref.y, 3u);
            child_payload = Graph.metadata(ref.y, 4u);
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        SCOPED_TYPE_PATH_SET(path, depth, slot);
        depth++;
        ref = uint3(child_tag, child_payload, ref.z);
    }
}

public bool scoped_type_refs_equal_graphs_stackless<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context,
    uint left_type_capacity, uint right_type_capacity, uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    SCOPED_TYPE_PATH(path);
    uint depth = 0u;
    uint resume = INVALID;
    uint4 pair = uint4(left_tag, left_payload, right_tag, right_payload);
    uint2 context = uint2(left_context, right_context);
    for (;;)
    {
        if (pair.x == 2u && context.x != INVALID)
        {
            if (pair.y >= token_capacity ||
                !LeftGraph.substitute_type_parameter(context.x, pair.y, pair.x, pair.y) ||
                (pair.x != 1u && pair.x != 2u && pair.x != 3u)) return false;
            context.x = INVALID;
        }
        if (pair.z == 2u && context.y != INVALID)
        {
            if (pair.w >= token_capacity ||
                !RightGraph.substitute_type_parameter(context.y, pair.w, pair.z, pair.w) ||
                (pair.z != 1u && pair.z != 2u && pair.z != 3u)) return false;
            context.y = INVALID;
        }
        uint count = 0u;
        bool compare_constant = false; bool count_identity = false;
        uint2 constant_left = uint2(0u, INVALID); uint2 constant_right = uint2(0u, INVALID);
        if (application_argument_is_constant(pair.x) || application_argument_is_constant(pair.z))
        {
            if (!application_constant_argument(pair.x, pair.y, constant_left.x, constant_left.y) ||
                !application_constant_argument(pair.z, pair.w, constant_right.x, constant_right.y))
                return false;
            compare_constant = true;
        }
        else if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
            return false;
        else if (pair.x != 3u)
        {
            if (pair.x != 1u && pair.x != 2u && !application_argument_is_constant(pair.x)) return false;
            if (pair.y != pair.w) return false;
            if (pair.x == 2u && (pair.y >= token_capacity ||
                (!LeftGraph.parameter_is_valid(pair.y, false) ||
                    !RightGraph.parameter_is_valid(pair.w, false)))) return false;
        }
        else
        {
            if (pair.y >= left_type_capacity || pair.w >= right_type_capacity) return false;
            uint kind = LeftGraph.metadata(pair.y, 0u);
            if (kind < 1u || kind > 4u || kind != RightGraph.metadata(pair.w, 0u)) return false;
            if (kind == 1u)
            {
                uint left_decl = LeftGraph.metadata(pair.y, 1u);
                uint right_decl = RightGraph.metadata(pair.w, 1u);
                if (left_decl != INVALID || right_decl != INVALID)
                {
                    if (left_decl >= token_capacity || left_decl != right_decl) return false;
                }
                else
                {
                    for (uint field = 7u; field <= 9u; field++)
                    {
                        uint identity = LeftGraph.metadata(pair.y, field);
                        if (identity == INVALID || identity != RightGraph.metadata(pair.w, field)) return false;
                    }
                }
                count = LeftGraph.metadata(pair.y, 2u);
                if (count > NOMINAL_APPLICATION_ARGUMENT_LIMIT ||
                    count != RightGraph.metadata(pair.w, 2u)) return false;
            }
            else
            {
                if (kind == 2u)
                {
                    constant_left = uint2(LeftGraph.metadata(pair.y, 5u), LeftGraph.metadata(pair.y, 6u));
                    constant_right = uint2(RightGraph.metadata(pair.w, 5u), RightGraph.metadata(pair.w, 6u));
                    compare_constant = true; count_identity = true;
                }
                count = 1u;
            }
        }
        if (compare_constant && resume == INVALID &&
            !scoped_constant_refs_or_counts_equal<LeftGraph, RightGraph>(
                uint3(constant_left, context.x), uint3(constant_right, context.y), token_capacity,
                count_identity)) return false;
        uint slot = select(resume == INVALID, 0u, SCOPED_TYPE_PATH_SLOT(path, depth));
        bool resumed = depth == resume;
        slot += uint(resumed);
        resume = select(resumed, INVALID, resume);
        if (slot == count)
        {
            if (depth == 0u) return true;
            resume = depth - 1u; depth = 0u;
            pair = uint4(left_tag, left_payload, right_tag, right_payload);
            context = uint2(left_context, right_context);
            continue;
        }
        uint tag_l; uint payload_l; uint tag_r; uint payload_r;
        if (LeftGraph.metadata(pair.y, 0u) == 1u)
        {
            if (!LeftGraph.argument(pair.y, slot, tag_l, payload_l) ||
                !RightGraph.argument(pair.w, slot, tag_r, payload_r)) return false;
        }
        else
        {
            tag_l = LeftGraph.metadata(pair.y, 3u); payload_l = LeftGraph.metadata(pair.y, 4u);
            tag_r = RightGraph.metadata(pair.w, 3u); payload_r = RightGraph.metadata(pair.w, 4u);
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        SCOPED_TYPE_PATH_SET(path, depth, slot);
        depth++;
        pair = uint4(tag_l, payload_l, tag_r, payload_r);
    }
}

// One graph namespace, as scoped_type_refs_equal.
public bool scoped_type_refs_equal_stackless<Graph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context, uint type_capacity,
    uint token_capacity)
{
    return scoped_type_refs_equal_graphs_stackless<Graph, Graph>(
        left_tag, left_payload, left_context, right_tag, right_payload, right_context,
        type_capacity, type_capacity, token_capacity);
}
