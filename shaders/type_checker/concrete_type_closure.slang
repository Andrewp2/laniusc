// A compound is concrete when every type argument and element reference is
// concrete. Being another instance is not itself a reason to reject a field.
// Unsubstituted parameters, unavailable rows, cycles, and excessive depth fail
// closed before machine layout is considered.
import type_checker.concrete_type_equality;
import constant_value;

// The graph owns source/generated operand storage. Closure uses the same
// metadata and argument contract for immutable readers and private producers.
public bool concrete_instance_is_closed<Graph : ITypeStructureGraph,
    Constants : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(uint instance, uint capacity, uint tokens)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint2 refs[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint children[DEPTH_LIMIT];
    uint depth = 0u;
    refs[0u] = uint2(3u, instance);
    next[0u] = INVALID;
    for (;;)
    {
        uint2 current = refs[depth];
        if (next[depth] == INVALID)
        {
            if (current.y == INVALID) return false;
            children[depth] = 0u;
            next[depth] = 0u;
            if (current.x == 1u)
            {
                if (current.y == 0u) return false;
            }
            else if (application_argument_is_constant(current.x))
            {
                uint2 constant;
                ConstantReferenceDescriptor descriptor;
                if (!application_constant_argument(current.x, current.y, constant.x, constant.y) ||
                    !inspect_constant_reference<Constants, Environment>(uint3(constant, 0u), tokens, descriptor) ||
                    descriptor.disposition != CONSTANT_REFERENCE_CONCRETE || descriptor.pending_fit != 0u)
                    return false;
            }
            else if (current.x == 3u && current.y < capacity)
            {
                uint kind = Graph.metadata(current.y, 0u);
                if (kind == 1u)
                {
                    children[depth] = Graph.metadata(current.y, 2u);
                    if (children[depth] > capacity) return false;
                }
                else if (kind == 2u || kind == 3u || kind == 4u)
                {
                    if (kind == 2u)
                    {
                        ConstantReferenceDescriptor descriptor; uint count;
                        if (!inspect_constant_reference<Constants, Environment>(
                            uint3(Graph.metadata(current.y, 5u), Graph.metadata(current.y, 6u), 0u),
                            tokens, descriptor) || descriptor.disposition != CONSTANT_REFERENCE_CONCRETE ||
                            descriptor.pending_fit != 0u || !constant_value_to_count(descriptor.value, count)) return false;
                    }
                    children[depth] = 1u;
                }
                else return false;
            }
            else return false;
        }
        if (next[depth] == children[depth])
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint ordinal = next[depth]++;
        uint tag; uint payload;
        if (Graph.metadata(current.y, 0u) != 1u)
        {
            tag = Graph.metadata(current.y, 3u);
            payload = Graph.metadata(current.y, 4u);
        }
        else if (!Graph.argument(current.y, ordinal, tag, payload)) return false;
        if (depth + 1u == DEPTH_LIMIT) return false;
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (refs[ancestor].x == tag && refs[ancestor].y == payload) return false;
        depth++;
        refs[depth] = uint2(tag, payload);
        next[depth] = INVALID;
    }
}
