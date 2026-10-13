// Shared structural-head index for declaration insertion and candidate lookup.
// A head only narrows candidate discovery; complete checked constraints decide
// applicability. Header validation owns the validity of every child.
import type_checker.scoped_type_equality;
import type_checker.concrete_type_equality;

public struct MethodReceiverHead
{
    // 1 scalar, 2 owned parameter wildcard, 3 local nominal, 4 external
    // nominal, 5 fixed array, 6 slice, 7 reference.
    public uint shape;
    public uint3 identity;
    public uint arity;
}

public MethodReceiverHead method_receiver_wildcard_head()
{
    MethodReceiverHead head;
    head.shape = 2u;
    head.identity = uint3(0u, 0u, 0u);
    head.arity = 0u;
    return head;
}

public bool method_receiver_head<Graph : IParameterScopedTypeGraph>(
    uint tag, uint payload, uint type_capacity, uint token_capacity,
    out MethodReceiverHead head)
{
    static const uint INVALID = 0xffffffffu;
    head.shape = 0u;
    head.identity = uint3(0u, 0u, 0u);
    head.arity = 0u;
    if (payload == INVALID) return false;
    if (tag == 1u)
    {
        // Encoded nominal names are incomplete graph references, not scalars.
        if (payload == 0u || payload >= 4096u) return false;
        head.shape = 1u;
        head.identity.x = payload;
        return true;
    }
    if (tag == 2u)
    {
        // Header validation proves impl ownership before a declaration can
        // contribute a wildcard candidate. This checks leaf identity only.
        if (payload >= token_capacity || !Graph.parameter_is_valid(payload, false))
            return false;
        head = method_receiver_wildcard_head();
        return true;
    }
    if (tag != 3u || payload >= type_capacity) return false;
    uint kind = Graph.metadata(payload, 0u);
    if (kind == 1u)
    {
        uint declaration = Graph.metadata(payload, 1u);
        head.arity = Graph.metadata(payload, 2u);
        if (head.arity > NOMINAL_APPLICATION_ARGUMENT_LIMIT) return false;
        if (declaration != INVALID)
        {
            if (declaration >= token_capacity) return false;
            head.shape = 3u;
            head.identity.x = declaration;
        }
        else
        {
            head.shape = 4u;
            head.identity = uint3(Graph.metadata(payload, 7u),
                Graph.metadata(payload, 8u), Graph.metadata(payload, 9u));
            if (any(head.identity == uint3(INVALID, INVALID, INVALID))) return false;
        }
        return true;
    }
    if (kind < 2u || kind > 4u) return false;
    head.shape = kind + 3u;
    return true;
}

public bool method_receiver_heads_equal(MethodReceiverHead left, MethodReceiverHead right)
{
    return left.shape == right.shape && all(left.identity == right.identity) &&
        left.arity == right.arity;
}

public uint method_lookup_capacity(uint method_capacity)
{
    return max(method_capacity * 2u, 1u);
}

public uint method_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint method_lookup_bucket(MethodReceiverHead head, uint name_id, uint method_capacity)
{
    uint hash = method_lookup_mix(head.shape ^ 0x9e3779b9u);
    hash ^= method_lookup_mix(head.identity.x ^ 0xc2b2ae35u);
    hash ^= method_lookup_mix(head.identity.y ^ 0x27d4eb2fu);
    hash ^= method_lookup_mix(head.identity.z ^ 0xd3a2646cu);
    hash ^= method_lookup_mix(head.arity ^ 0x85ebca6bu);
    hash ^= method_lookup_mix(name_id ^ 0x165667b1u);
    return method_lookup_mix(hash) % method_lookup_capacity(method_capacity);
}
