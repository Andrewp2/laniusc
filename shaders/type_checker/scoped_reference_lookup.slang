// Resolve declaration-side references under a checked type application. The
// graph and lookup index belong to the caller; this module owns no buffers.
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;

public bool instance_scoped_reference<Graph : IScopedTypeGraph>(
    uint tag, uint payload, uint context, uint type_capacity, uint token_capacity,
    StructuredBuffer<uint> lookup_head, StructuredBuffer<uint> lookup_next,
    out uint result_tag, out uint result_payload)
{
    static const uint INVALID = 0xffffffffu;
    result_tag = 0u; result_payload = INVALID;
    // This boundary accepts nominal environments. Graph walks delegate to
    // the same reader used by other checked consumers; no wrapper creates
    // another hash/equality specialization for identical resident rows.
    if (context != INVALID && ((context & 0x80000000u) != 0u || context >= type_capacity)) return false;
    if (tag == 2u && context != INVALID)
    {
        uint slot = payload < token_capacity ? Graph.parameter_slot(payload) : INVALID;
        if (context >= type_capacity || slot == INVALID ||
            !Graph.environment_argument(context, slot, tag, payload)) return false;
        // The argument is already checked in caller scope. Applying the
        // receiver environment again would capture a caller's parameter.
        context = INVALID;
    }
    if ((tag == 1u && payload != 0u && payload != INVALID) ||
        (tag == 2u && payload < token_capacity && Graph.parameter_slot(payload) != INVALID))
    {
        result_tag = tag; result_payload = payload;
        return true;
    }
    if (tag != 3u || payload >= type_capacity) return false;
    uint kind = Graph.metadata(payload, 0u);
    if (kind < 1u || kind > 4u) return false;
    if (context == INVALID)
    {
        // A checked caller reference needs no substitution or reinterning.
        result_tag = tag; result_payload = payload;
        return true;
    }
    uint hash;
    if (!scoped_type_ref_hash<Graph>(
        tag, payload, context, type_capacity, token_capacity, hash)) return false;
    uint buckets; uint stride;
    lookup_head.GetDimensions(buckets, stride);
    if (buckets == 0u) return false;
    uint link = lookup_head[hash % buckets];
    // Hash collisions select candidates only; complete scoped equality
    // decides identity, including nominal types and every argument.
    for (uint steps = 0u; steps < type_capacity && link != 0u; steps++)
    {
        uint candidate = link - 1u;
        if (candidate >= type_capacity) return false;
        if (scoped_type_refs_equal<Graph>(
            3u, payload, context, 3u, candidate, INVALID, type_capacity, token_capacity))
        {
            result_tag = 3u; result_payload = candidate;
            return true;
        }
        link = lookup_next[candidate];
    }
    return false;
}
