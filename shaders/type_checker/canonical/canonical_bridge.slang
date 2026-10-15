// Read path from canonical IDs to the checked type graph's row interface
// (docs/canonical-type-ids.md, "Bridge"). It is not a second producer: it
// decodes published records only.
//
// A tag-3 payload at or above CT_ROW_BASE names the canonical ID
// payload - CT_ROW_BASE; so do constant references of kind 1 (a value or a
// count class) and kind 3 (a cast). Rows below the base are the checked
// graph's own and are read through ScopedCheckedTypeGraph unchanged. A
// consumer opts in by naming CanonicalBridgeTypeGraph where it names
// ScopedCheckedTypeGraph and passing CT_BRIDGE_TYPE_CAPACITY as the type
// capacity; kernels that do not import this module are unaffected.
//
// A bridged named type spells a local declaration by its token (field 1)
// and an imported one by its (library, unit, local) triple (fields 7-9),
// as checked rows do. An imported reference to the job's own declaration
// reads as the local spelling, since both share one ID. Array lengths are
// count classes (a count reads as its u32 value), compared by count
// identity as checked lengths are. Dependency slot parameters have no
// checked spelling and fail closed.
//
// Every bridged read is a few loads with no nested helpers: the old walkers
// expand a graph read at each of their call sites.
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import primitive_types;

// The type capacity a bridged comparison passes to the walkers: the bridge
// bounds checked rows itself.
public static const uint CT_BRIDGE_TYPE_CAPACITY = 0xffffffffu;

// The record head of a stored ID, or zero (kind 0) for anything else.
uint4 ct_bridge_head(uint id)
{
    uint records; uint stride;
    ct_head.GetDimensions(records, stride);
    bool stored = id - (SCALAR_USIZE + 1u) < records - (SCALAR_USIZE + 1u);
    return select(bool4(stored, stored, stored, stored), ct_head[select(stored, id, 0u)],
        uint4(0u, 0u, 0u, 0u));
}

// The checked operand (tag, payload) of canonical reference `ref`: 1 scalar,
// 2 type parameter token, 3 bridged type, and the constant argument tags
// (1 value or count class, 2 constant parameter token, 3 cast). The payload
// is INVALID for a reference with no checked spelling (a dependency slot
// parameter, a sentinel, an environment).
public uint2 ct_bridge_operand(uint ref)
{
    // Two bits per record kind below 16: 1 a type (NAMED, ARRAY, SLICE,
    // REF), 2 a value or count class, 3 a cast.
    uint kind = ct_bridge_head(ref).x & 0xffu;
    uint code = select(kind < 16u, (0x2e0550u >> (kind * 2u)) & 3u, 0u);
    uint2 operand = uint2(select(code == 1u, 3u, APPLICATION_CONSTANT_ARGUMENT | select(code == 2u, 1u, 3u)),
        select(code == 0u, 0xffffffffu, CT_ROW_BASE + ref));
    // Domains 4 and 6: a type or constant parameter of this job.
    uint domain = ref >> 29u;
    bool parameter = (domain | 2u) == 6u;
    uint parameter_tag = select(domain == 4u, 2u, APPLICATION_CONSTANT_ARGUMENT | 2u);
    operand = select(bool2(parameter, parameter), uint2(parameter_tag, ref & CT_PARAM_TOKEN_MASK), operand);
    bool scalar = ref - 1u < SCALAR_USIZE;
    return select(bool2(scalar, scalar), uint2(1u, ref), operand);
}

// Metadata of a bridged ID, in checked row fields: kind (0), local
// declaration (1), operand count (2), element (3/4), named domains or array
// length (5/6), external identity (7/8/9). Straight-line selects: a walker
// expands this at each of its call sites.
public uint ct_bridge_metadata(uint id, uint field)
{
    static const uint INVALID = 0xffffffffu;
    uint4 head = ct_bridge_head(id);
    // NAMED, ARRAY, SLICE, REF are checked kinds 1..4.
    uint checked = (head.x & 0xffu) - (CT_KIND_NAMED - 1u);
    bool valid = checked - 1u < 4u;
    bool named = checked == 1u;
    uint safe = select(valid, id, 0u);
    // Named: (local declaration token or INVALID, constant operand mask).
    uint2 extra = ct_extra[safe];
    // The element (3/4) of every compound, the length (5/6) of an array.
    bool element = field - 3u < 2u;
    bool child = valid && !named && (element || checked == 2u);
    uint index = select(child, ct_meta[safe].x + select(element, 0u, 1u), 0u);
    uint2 operand = select(bool2(child, child), ct_bridge_operand(ct_args[index]), uint2(0u, INVALID));
    uint operand_tag = select(operand.y == INVALID, 0u,
        select(element, operand.x, operand.x & ~APPLICATION_CONSTANT_ARGUMENT));
    // Named domains: type-first order unless a constant precedes a type.
    uint arity = (head.x >> 8u) & 0xffu;
    uint types = head.x >> 16u;
    uint operands = select(arity >= 32u, 0xffffffffu, (1u << (arity & 31u)) - 1u);
    uint tail = select(types >= 32u, 0u, operands & ~((1u << (types & 31u)) - 1u));
    uint domains = types | select(extra.y != tail, APPLICATION_INTERLEAVED_DOMAINS, 0u);
    uint value = select(field == 0u, checked, INVALID);
    value = select(field == 1u && named, extra.x, value);
    value = select(field == 2u, select(named, arity, 0u), value);
    value = select(field == 3u || field == 5u, operand_tag, value);
    value = select(field == 4u || field == 6u, operand.y, value);
    value = select(named && field == 5u, domains, value);
    value = select(named && field == 6u, extra.y, value);
    value = select(named && field - 7u < 3u && extra.x == INVALID, head[(field - 6u) & 3u], value);
    return select(valid, value, select(field == 0u, 0u, INVALID));
}

public struct CanonicalBridgeTypeGraph : IScopedTypeGraph
{
    public static uint metadata(uint instance, uint field)
    {
        if (instance >= CT_ROW_BASE) return ct_bridge_metadata(instance - CT_ROW_BASE, field);
        if (instance < checked_type_capacity()) return ScopedCheckedTypeGraph.metadata(instance, field);
        return field == 0u ? 0u : 0xffffffffu;
    }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = 0xffffffffu;
        if (instance < CT_ROW_BASE)
            return instance < checked_type_capacity() &&
                ScopedCheckedTypeGraph.argument(instance, slot, tag, payload);
        uint id = instance - CT_ROW_BASE;
        uint4 head = ct_bridge_head(id);
        if ((head.x & 0xffu) != CT_KIND_NAMED || slot >= ((head.x >> 8u) & 0xffu)) return false;
        uint2 operand = ct_bridge_operand(ct_args[ct_meta[id].x + slot]);
        tag = operand.x; payload = operand.y;
        return operand.y != 0xffffffffu;
    }
    public static bool constant_value(uint row, out uint3 value)
    {
        if (row < CT_ROW_BASE) return checked_constant_atom_value(row, value);
        // Values were validated when interned; a count class reads as the
        // u32 value of its count.
        uint4 head = ct_bridge_head(row - CT_ROW_BASE);
        uint kind = head.x & 0xffu;
        bool valid = kind == CC_KIND_VALUE || kind == CC_KIND_COUNT;
        value = !valid ? uint3(0u, 0u, 0u) : kind == CC_KIND_COUNT ? uint3(SCALAR_U32, head.y, 0u) : head.yzw;
        return valid;
    }
    [ForceInline]
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    {
        if (row < CT_ROW_BASE) return checked_constant_projection(row, scalar, child);
        scalar = 0u; child = uint2(0u, 0xffffffffu);
        uint id = row - CT_ROW_BASE;
        if ((ct_bridge_head(id).x & 0xffu) != CC_KIND_CAST) return false;
        uint2 operand = ct_bridge_operand(ct_args[ct_meta[id].x]);
        if (!application_argument_is_constant(operand.x) || operand.y == 0xffffffffu) return false;
        scalar = ct_head[id].y;
        child = uint2(operand.x & ~APPLICATION_CONSTANT_ARGUMENT, operand.y);
        return true;
    }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<CanonicalBridgeTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference,
        out uint tag, out uint payload)
    {
        return source_substitute_type_parameter<CanonicalBridgeTypeGraph>(environment, reference, tag, payload);
    }
    public static bool substitute_constant_parameter(uint environment, uint reference,
        out uint kind, out uint value)
    {
        return source_substitute_constant_parameter<CanonicalBridgeTypeGraph>(
            environment, reference, kind, value);
    }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        return application_environment_type_argument<CanonicalBridgeTypeGraph>(environment, slot, tag, payload);
    }
    [ForceInline]
    public static uint constant_parameter_slot(uint token) { return type_const_param_slot_by_token[token]; }
    [ForceInline]
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return application_environment_constant<CanonicalBridgeTypeGraph>(environment, slot, kind, value); }
    [ForceInline]
    public static uint parameter_slot(uint token) { return type_generic_param_slot_by_token[token]; }
}
