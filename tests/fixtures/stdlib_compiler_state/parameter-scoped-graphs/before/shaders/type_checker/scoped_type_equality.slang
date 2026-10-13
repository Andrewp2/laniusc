// Compare a declaration-side type under its enclosing concrete environment.
// The environment applies to symbolic leaves only. Once a leaf is replaced by
// an argument, that argument is already checked in the caller's scope.
import type_checker.concrete_type_equality;

public interface IScopedTypeGraph : IConcreteTypeGraph
{
    static uint parameter_slot(uint parameter_token);
    static uint constant_parameter_slot(uint parameter_token);
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value);
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload);
}

// Lengths retain declaration identity without a substitution environment.
// Bound references are caller-side literals or scoped parameters and receive
// no second substitution.
public bool scoped_constant_length<Graph : IScopedTypeGraph>(uint environment,
    uint tokens, inout uint kind, inout uint value)
{
    static const uint INVALID = 0xffffffffu;
    if (value == INVALID) return false;
    if (kind == 1u) return true;
    if (kind != 2u || value >= tokens) return false;
    if (environment == INVALID) return true;
    uint slot = Graph.constant_parameter_slot(value);
    uint bound_kind; uint bound;
    if (slot >= 32u || !Graph.environment_constant(environment, slot, bound_kind, bound)) return false;
    kind = bound_kind;
    value = bound;
    return value != INVALID && (kind == 1u ||
        (kind == 2u && value < tokens && Graph.constant_parameter_slot(value) < 32u));
}

public bool scoped_type_refs_equal<Graph : IScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context, uint type_capacity,
    uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint4 pairs[DEPTH_LIMIT];
    uint2 contexts[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint depth = 0u;
    pairs[0u] = uint4(left_tag, left_payload, right_tag, right_payload);
    contexts[0u] = uint2(left_context, right_context);
    next[0u] = INVALID;
    for (;;)
    {
        uint4 pair = pairs[depth];
        uint2 context = contexts[depth];
        if (next[depth] == INVALID)
        {
            if (pair.x == 2u && context.x != INVALID)
            {
                uint slot = pair.y < token_capacity ? Graph.parameter_slot(pair.y) : INVALID;
                if (slot == INVALID ||
                    !Graph.environment_argument(context.x, slot, pair.x, pair.y)) return false;
                context.x = INVALID;
            }
            if (pair.z == 2u && context.y != INVALID)
            {
                uint slot = pair.w < token_capacity ? Graph.parameter_slot(pair.w) : INVALID;
                if (slot == INVALID ||
                    !Graph.environment_argument(context.y, slot, pair.z, pair.w)) return false;
                context.y = INVALID;
            }
            if (application_argument_is_constant(pair.x))
            {
                uint kind = pair.x & ~APPLICATION_CONSTANT_ARGUMENT;
                if (!scoped_constant_length<Graph>(context.x, token_capacity, kind, pair.y)) return false;
                pair.x = APPLICATION_CONSTANT_ARGUMENT | kind;
                context.x = INVALID;
            }
            if (application_argument_is_constant(pair.z))
            {
                uint kind = pair.z & ~APPLICATION_CONSTANT_ARGUMENT;
                if (!scoped_constant_length<Graph>(context.y, token_capacity, kind, pair.w)) return false;
                pair.z = APPLICATION_CONSTANT_ARGUMENT | kind;
                context.y = INVALID;
            }
            pairs[depth] = pair;
            contexts[depth] = context;
            if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                return false;
            counts[depth] = 0u;
            next[depth] = 0u;
            if (pair.x != 3u)
            {
                if (pair.x != 1u && pair.x != 2u && !application_argument_is_constant(pair.x)) return false;
                if (pair.y != pair.w) return false;
                if (pair.x == 2u && (pair.y >= token_capacity ||
                    Graph.parameter_slot(pair.y) == INVALID)) return false;
            }
            else
            {
                if (pair.y >= type_capacity || pair.w >= type_capacity) return false;
                uint kind = Graph.metadata(pair.y, 0u);
                if (kind < 1u || kind > 4u || kind != Graph.metadata(pair.w, 0u)) return false;
                if (kind == 1u)
                {
                    uint left_decl = Graph.metadata(pair.y, 1u);
                    uint right_decl = Graph.metadata(pair.w, 1u);
                    if (left_decl != INVALID || right_decl != INVALID)
                    {
                        if (left_decl >= token_capacity || left_decl != right_decl) return false;
                    }
                    else
                    {
                        for (uint field = 7u; field <= 9u; field++)
                        {
                            uint identity = Graph.metadata(pair.y, field);
                            if (identity == INVALID || identity != Graph.metadata(pair.w, field)) return false;
                        }
                    }
                    counts[depth] = Graph.metadata(pair.y, 2u);
                    if (counts[depth] > type_capacity ||
                        counts[depth] != Graph.metadata(pair.w, 2u)) return false;
                }
                else
                {
                    if (kind == 2u)
                    {
                        uint2 left = uint2(Graph.metadata(pair.y, 5u), Graph.metadata(pair.y, 6u));
                        uint2 right = uint2(Graph.metadata(pair.w, 5u), Graph.metadata(pair.w, 6u));
                        if (!scoped_constant_length<Graph>(context.x, token_capacity, left.x, left.y) ||
                            !scoped_constant_length<Graph>(context.y, token_capacity, right.x, right.y) ||
                            any(left != right)) return false;
                    }
                    counts[depth] = 1u;
                }
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint slot = next[depth]++;
        uint tag_l; uint payload_l; uint tag_r; uint payload_r;
        if (Graph.metadata(pair.y, 0u) == 1u)
        {
            if (!Graph.argument(pair.y, slot, tag_l, payload_l) ||
                !Graph.argument(pair.w, slot, tag_r, payload_r)) return false;
        }
        else
        {
            tag_l = Graph.metadata(pair.y, 3u); payload_l = Graph.metadata(pair.y, 4u);
            tag_r = Graph.metadata(pair.w, 3u); payload_r = Graph.metadata(pair.w, 4u);
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        depth++;
        pairs[depth] = uint4(tag_l, payload_l, tag_r, payload_r);
        contexts[depth] = context;
        next[depth] = INVALID;
    }
}
