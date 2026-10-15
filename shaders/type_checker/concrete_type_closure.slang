// A compound is concrete when every type argument and element reference is
// concrete. Being another instance is not itself a reason to reject a field.
// Unsubstituted parameters, unavailable rows, cycles, and excessive depth fail
// closed before machine layout is considered.
import type_checker.concrete_type_equality;
import constant_value;

static const uint CONCRETE_CLOSURE_INVALID = 0xffffffffu;
// References deeper than this below the instance fail closed.
static const uint CONCRETE_CLOSURE_DEPTH_LIMIT = 64u;

// Whether one reference may appear in a closed type, given its instance kind
// and child count (both 0 unless it names an instance below capacity). A
// constant argument and a fixed array's length share one constant check.
[ForceInline]
bool concrete_closure_node_is_valid<Graph : ITypeStructureGraph,
    Constants : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(
    uint2 node, uint kind, uint children, uint capacity, uint tokens)
{
    if (node.y == CONCRETE_CLOSURE_INVALID) return false;
    if (node.x == 1u) return node.y != 0u;
    bool constant_argument = application_argument_is_constant(node.x);
    uint2 constant;
    if (constant_argument)
    {
        if (!application_constant_argument(node.x, node.y, constant.x, constant.y)) return false;
    }
    else
    {
        if (node.x != 3u || node.y >= capacity) return false;
        if (kind == 1u) return children <= capacity;
        if (kind != 2u) return kind == 3u || kind == 4u;
        constant = uint2(Graph.metadata(node.y, 5u), Graph.metadata(node.y, 6u));
    }
    ConstantReferenceDescriptor descriptor; uint length;
    return inspect_constant_reference<Constants, Environment>(uint3(constant, 0u), tokens, descriptor) &&
        descriptor.disposition == CONSTANT_REFERENCE_CONCRETE && descriptor.pending_fit == 0u &&
        (constant_argument || constant_value_to_count(descriptor.value, length));
}

// The graph owns source/generated operand storage. Closure uses the same
// metadata and argument contract for immutable readers and private producers.
//
// A depth-first walk of every reference reachable from the instance, without
// a stack. The current path is packed into one uint: the ordinal taken at a
// node with `count` children uses the bits needed for count - 1 (none for a
// single child), starting at `offset`, the bits used by the nodes above it.
// Leaving a node walks again from the instance along those bits to its
// parent, one level per iteration. Each iteration reads one node's kind and
// child count and takes at most one child, so every graph read has a single
// call site. A cycle repeats until the depth limit, so it fails closed
// without an ancestor check; so does a path needing more than 31 bits.
// Shifts rather than a mixed-radix number: integer division by a
// loop-carried count made NVIDIA 615 fail pipeline creation (NVVM error 3).
public bool concrete_instance_is_closed<Graph : ITypeStructureGraph,
    Constants : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(uint instance, uint capacity, uint tokens)
{
    uint2 node = uint2(3u, instance);
    uint depth = 0u;
    uint path = 0u;
    uint offset = 0u;
    uint children = 0u;
    uint next = 0u;
    bool entering = true;
    // While returning, `node` walks from the instance towards the parent of
    // the node left, and `next` counts the levels still to go.
    bool returning = false;
    for (;;)
    {
        uint kind = 0u;
        uint count = 0u;
        if (node.x == 3u && node.y < capacity)
        {
            kind = Graph.metadata(node.y, 0u);
            count = kind == 1u ? Graph.metadata(node.y, 2u) : (kind - 2u < 3u ? 1u : 0u);
        }
        if (entering)
        {
            if (!concrete_closure_node_is_valid<Graph, Constants, Environment>(node, kind, count, capacity, tokens))
                return false;
            entering = false;
            children = count;
            next = 0u;
        }
        if (!returning && next == children)
        {
            if (depth == 0u) return true;
            returning = true;
            node = uint2(3u, instance);
            offset = 0u;
            next = depth - 1u;
            continue;
        }
        if (count == 0u) return false;
        uint width = firstbithigh(count - 1u) + 1u;
        uint ordinal = returning ? (path >> offset) & ((1u << width) - 1u) : next;
        if (returning && next == 0u)
        {
            // `node` is the parent, and `ordinal` led from it to the node left.
            path -= ordinal << offset;
            depth -= 1u;
            children = count;
            next = ordinal + 1u;
            returning = false;
            continue;
        }
        if (!returning &&
            (depth + 1u == CONCRETE_CLOSURE_DEPTH_LIMIT || offset + width > 31u))
            return false;
        uint2 child;
        if (kind != 1u)
            child = uint2(Graph.metadata(node.y, 3u), Graph.metadata(node.y, 4u));
        else if (!Graph.argument(node.y, ordinal, child.x, child.y))
            return false;
        if (returning)
        {
            next -= 1u;
        }
        else
        {
            path += ordinal << offset;
            depth += 1u;
            entering = true;
        }
        offset += width;
        node = child;
    }
}
