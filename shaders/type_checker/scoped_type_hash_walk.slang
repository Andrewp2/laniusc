// Included walker body (not a module). The includer defines
// SCOPED_TYPE_HASH_WALK (the function name), SCOPED_TYPE_HASH_FRAMES (frame
// declarations), the readers SH_REF/SH_NEXT/SH_COUNT, the writers
// SH_SET_NEXT/SH_SET_COUNT, SH_PUSH(d, ref) (ref, next = INVALID) and
// SH_CLASSIFIED(d, ref) (ref, next = 0, count = 0). scoped_type_hash.slang
// expands it over local arrays; scoped_type_scratch.slang expands it over the
// thread scratch table.
public bool SCOPED_TYPE_HASH_WALK<Graph : IParameterScopedTypeGraph>(
    uint tag, uint payload, uint context, uint type_capacity,
    uint token_capacity, out uint result)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    SCOPED_TYPE_HASH_FRAMES
    uint depth = 0u;
    uint hash = 2166136261u;
    result = 0u;
    SH_PUSH(0u, uint3(tag, payload, context));
    for (;;)
    {
        uint3 ref = SH_REF(depth);
        bool classify = SH_NEXT(depth) == INVALID;
        if (classify)
        {
            if (ref.x == 2u && ref.z != INVALID)
            {
                if (ref.y >= token_capacity ||
                    !Graph.substitute_type_parameter(ref.z, ref.y, ref.x, ref.y) ||
                    (ref.x != 1u && ref.x != 2u && ref.x != 3u)) return false;
                ref.z = INVALID;
            }
            if (ref.y == INVALID) return false;
            SH_CLASSIFIED(depth, ref);
        }
        // A node frame (tag 3, in range) reads its fields once per step: its
        // header when classified, then the reference of the child it enters.
        TypeNodeFields node = type_node_step_fields<Graph>(ref.y, ref.x == 3u && ref.y < type_capacity &&
            (classify || SH_NEXT(depth) != SH_COUNT(depth)), classify);
        if (classify)
        {
            hash = scoped_type_hash_mix(hash,
                application_argument_is_constant(ref.x) ? APPLICATION_CONSTANT_ARGUMENT : ref.x);
            // The constant leaf or array length whose identity ends this
            // node's header; both share one hash site.
            bool constant = false; bool count_identity = false;
            uint3 constant_ref = uint3(0u, INVALID, INVALID);
            if (ref.x == 1u)
            {
                if (ref.y == 0u) return false;
                hash = scoped_type_hash_mix(hash, ref.y);
            }
            else if (ref.x == 2u)
            {
                // An unbound leaf keeps its declaration identity. Two `T`
                // parameters in different scopes must never share a key.
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
                    SH_SET_COUNT(depth, node.count);
                    if (node.count > NOMINAL_APPLICATION_ARGUMENT_LIMIT) return false;
                    hash = scoped_type_hash_mix(hash, node.count);
                }
                else if (node.kind == 2u || node.kind == 3u || node.kind == 4u)
                {
                    if (node.kind == 2u)
                    {
                        constant = true; count_identity = true;
                        constant_ref = uint3(node.length, ref.z);
                    }
                    SH_SET_COUNT(depth, 1u);
                }
                else return false;
            }
            else return false;
            if (constant)
            {
                uint identity_hash;
                if (!scoped_constant_ref_or_count_hash<Graph>(constant_ref, token_capacity,
                    count_identity, identity_hash)) return false;
                hash = scoped_type_hash_mix(hash, identity_hash);
            }
        }
        if (SH_NEXT(depth) == SH_COUNT(depth))
        {
            hash = scoped_type_hash_mix(hash, INVALID);
            if (depth == 0u) { result = hash; return true; }
            depth--;
            continue;
        }
        uint slot = SH_NEXT(depth);
        SH_SET_NEXT(depth, slot + 1u);
        uint child_tag = node.element.x; uint child_payload = node.element.y;
        if (node.kind == 1u && !Graph.argument(ref.y, slot, child_tag, child_payload)) return false;
        if (depth + 1u == DEPTH_LIMIT) return false;
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (SH_REF(ancestor).x == child_tag && SH_REF(ancestor).y == child_payload &&
                SH_REF(ancestor).z == ref.z) return false;
        depth++;
        SH_PUSH(depth, uint3(child_tag, child_payload, ref.z));
    }
}
