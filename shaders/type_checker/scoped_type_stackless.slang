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
        // A node (tag 3, in range) reads its header and child reference once.
        TypeNodeFields node = type_node_step_fields<Graph>(ref.y, ref.x == 3u && ref.y < type_capacity, true);
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
            hash = scoped_type_hash_mix(hash, node.kind);
            if (node.kind == 1u)
            {
                hash = scoped_type_hash_mix(hash, node.declaration);
                if (node.declaration == INVALID)
                {
                    if (any(node.identity == INVALID)) return false;
                    hash = scoped_type_hash_mix(scoped_type_hash_mix(scoped_type_hash_mix(
                        hash, node.identity.x), node.identity.y), node.identity.z);
                }
                else if (node.declaration >= token_capacity) return false;
                count = node.count;
                if (count > NOMINAL_APPLICATION_ARGUMENT_LIMIT) return false;
                hash = scoped_type_hash_mix(hash, count);
            }
            else if (node.kind == 2u || node.kind == 3u || node.kind == 4u)
            {
                if (node.kind == 2u)
                {
                    constant = true; count_identity = true;
                    constant_ref = uint3(node.length, ref.z);
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
        uint child_tag = node.element.x; uint child_payload = node.element.y;
        if (node.kind == 1u && !Graph.argument(ref.y, slot, child_tag, child_payload)) return false;
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
        // A node pair (both tag 3, in range) reads each side's header and
        // child reference once.
        TypeNodeFields left = type_node_step_fields<LeftGraph>(pair.y,
            pair.x == 3u && pair.y < left_type_capacity, true);
        TypeNodeFields right = type_node_step_fields<RightGraph>(pair.w,
            pair.z == 3u && pair.w < right_type_capacity, true);
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
            uint kind = left.kind;
            if (kind < 1u || kind > 4u || kind != right.kind) return false;
            if (kind == 1u)
            {
                if (left.declaration != INVALID || right.declaration != INVALID)
                {
                    if (left.declaration >= token_capacity || left.declaration != right.declaration) return false;
                }
                else if (any(left.identity == INVALID) || any(left.identity != right.identity)) return false;
                count = left.count;
                if (count > NOMINAL_APPLICATION_ARGUMENT_LIMIT || count != right.count) return false;
            }
            else
            {
                if (kind == 2u)
                {
                    constant_left = left.length; constant_right = right.length;
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
        uint tag_l = left.element.x; uint payload_l = left.element.y;
        uint tag_r = right.element.x; uint payload_r = right.element.y;
        if (left.kind == 1u && (!LeftGraph.argument(pair.y, slot, tag_l, payload_l) ||
            !RightGraph.argument(pair.w, slot, tag_r, payload_r))) return false;
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
