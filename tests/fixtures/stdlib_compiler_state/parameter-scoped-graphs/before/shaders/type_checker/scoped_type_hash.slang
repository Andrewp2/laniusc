import type_checker.concrete_type_equality;
// Index complete type structure under a declaration's parameter environment.
// Hashes choose a bucket only; callers must still compare complete references.
import type_checker.scoped_type_equality;

public uint scoped_type_hash_mix(uint hash, uint value)
{
    hash = (hash ^ value) * 16777619u;
    return hash ^ (hash >> 16u);
}

public bool scoped_type_ref_hash<Graph : IScopedTypeGraph>(
    uint tag, uint payload, uint context, uint type_capacity,
    uint token_capacity, out uint result)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint3 refs[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint depth = 0u;
    uint hash = 2166136261u;
    result = 0u;
    refs[0u] = uint3(tag, payload, context);
    next[0u] = INVALID;
    for (;;)
    {
        uint3 ref = refs[depth];
        if (next[depth] == INVALID)
        {
            if (ref.x == 2u && ref.z != INVALID)
            {
                uint slot = ref.y < token_capacity ? Graph.parameter_slot(ref.y) : INVALID;
                if (slot == INVALID ||
                    !Graph.environment_argument(ref.z, slot, ref.x, ref.y)) return false;
                ref.z = INVALID;
            }
            if (application_argument_is_constant(ref.x))
            {
                uint kind = ref.x & ~APPLICATION_CONSTANT_ARGUMENT;
                if (!scoped_constant_length<Graph>(ref.z, token_capacity, kind, ref.y)) return false;
                ref.x = APPLICATION_CONSTANT_ARGUMENT | kind; ref.z = INVALID;
            }
            if (ref.y == INVALID) return false;
            refs[depth] = ref;
            next[depth] = 0u;
            counts[depth] = 0u;
            hash = scoped_type_hash_mix(hash, ref.x);
            if (ref.x == 1u)
            {
                if (ref.y == 0u) return false;
                hash = scoped_type_hash_mix(hash, ref.y);
            }
            else if (ref.x == 2u)
            {
                // An unbound leaf keeps its declaration identity. Two `T`
                // parameters in different scopes must never share a key.
                if (ref.y >= token_capacity || Graph.parameter_slot(ref.y) == INVALID) return false;
                hash = scoped_type_hash_mix(hash, ref.y);
            }
            else if (application_argument_is_constant(ref.x))
                hash = scoped_type_hash_mix(hash, ref.y);
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
                    counts[depth] = Graph.metadata(ref.y, 2u);
                    if (counts[depth] > type_capacity) return false;
                    hash = scoped_type_hash_mix(hash, counts[depth]);
                }
                else if (kind == 2u || kind == 3u || kind == 4u)
                {
                    if (kind == 2u)
                    {
                        uint length_kind = Graph.metadata(ref.y, 5u);
                        uint length = Graph.metadata(ref.y, 6u);
                        if (!scoped_constant_length<Graph>(ref.z, token_capacity, length_kind, length)) return false;
                        hash = scoped_type_hash_mix(hash, length_kind);
                        hash = scoped_type_hash_mix(hash, length);
                    }
                    counts[depth] = 1u;
                }
                else return false;
            }
            else return false;
        }
        if (next[depth] == counts[depth])
        {
            hash = scoped_type_hash_mix(hash, INVALID);
            if (depth == 0u) { result = hash; return true; }
            depth--;
            continue;
        }
        uint slot = next[depth];
        next[depth] = slot + 1u;
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
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (refs[ancestor].x == child_tag && refs[ancestor].y == child_payload &&
                refs[ancestor].z == ref.z) return false;
        depth++;
        refs[depth] = uint3(child_tag, child_payload, ref.z);
        next[depth] = INVALID;
    }
}
