// Canonical-ID reads of the read-only checked type graph, for consumers that
// used to walk it: identity is `==` on canonical IDs, closure is ct_closed,
// and a declaration-side reference under a nominal environment is its
// canonical substitution, looked up (never interned) and read back as the
// row of its ID. See docs/canonical-type-ids.md.
//
// Each helper takes an ICheckedIds reader. After the late canonical stage
// every row and constant has its ID (LateIds). Inside the inference rounds a
// row may be newer than the early stage, so OnDemandIds interns what is
// missing (ct_checked.slang). Nothing here walks a type graph with a stack.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_subst;
import type_checker.checked_type_graph;
import type_checker.constant_parameter_slots;
import constant_value;

// The canonical reference of a checked operand (tag, payload).
public interface ICheckedIds
{
    static uint id(uint tag, uint payload);
}

// Kernels recorded after the late canonical stage.
public struct LateIds : ICheckedIds
{
    [ForceInline] public static uint id(uint tag, uint payload) { return ct_ref(tag, payload); }
}

// Kernels inside the inference rounds: interns the rows and constants that
// are not interned yet.
public struct OnDemandIds : ICheckedIds
{
    public static uint id(uint tag, uint payload)
    {
        uint spare = CT_NONE;
        return ct_intern_checked<CtCheckedRows>(tag, payload, spare);
    }
}

// The ICtSlots adapter of kernels on the read-only checked graph.
public struct CheckedSlots : ICtSlots
{
    public uint type_slot(uint token)
    {
        uint count; uint stride;
        type_generic_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_generic_param_slot_by_token[token] : CT_SLOT_NONE;
    }
    public uint const_slot(uint token)
    {
        uint count; uint stride;
        type_const_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_const_param_slot_by_token[token] : CT_SLOT_NONE;
    }
    public uint const_scalar(uint token)
    {
        uint count; uint stride;
        type_const_param_scalar_by_token.GetDimensions(count, stride);
        uint scalar = token < count ? type_const_param_scalar_by_token[token] : 0u;
        return constant_scalar_is_supported(scalar) ? scalar : 0u;
    }
}

// The IDs of rows `first` and `second`, read at one call site.
void checked_row_ids<I : ICheckedIds>(uint first, uint second, out uint first_id, out uint second_id)
{
    first_id = CT_UNKNOWN; second_id = CT_UNKNOWN;
    [loop]
    for (uint index = 0u; index < 2u; index++)
    {
        uint id = I.id(3u, index == 0u ? first : second);
        if (index == 0u) first_id = id;
        else second_id = id;
    }
}

// Whether checked row `row` is a complete closed type: no type or constant
// parameter, every constant concrete and fitting (the walker's closure).
public bool checked_row_closed<I : ICheckedIds>(uint row)
{
    return row < checked_type_capacity() && ct_closed(I.id(3u, row));
}

// Identity of two checked type references in caller scope. Scalars and
// parameters compare by spelling, as the walker did; rows by canonical ID.
public bool checked_refs_equal<I : ICheckedIds>(uint left_tag, uint left_payload,
    uint right_tag, uint right_payload, uint token_capacity)
{
    uint capacity = checked_type_capacity();
    uint left = CT_UNKNOWN; uint right = CT_UNKNOWN;
    if (left_tag == 3u && right_tag == 3u && left_payload < capacity && right_payload < capacity)
        checked_row_ids<I>(left_payload, right_payload, left, right);
    return checked_refs_equal_ids(left_tag, left_payload, left, right_tag, right_payload, right,
        token_capacity);
}

// checked_refs_equal over the rows' IDs, already read by the caller
// (anything for a non-row).
public bool checked_refs_equal_ids(uint left_tag, uint left_payload, uint left_id,
    uint right_tag, uint right_payload, uint right_id, uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    if (left_tag != right_tag || left_tag == 0u || left_payload == INVALID || right_payload == INVALID)
        return false;
    if (left_tag == 1u) return left_payload == right_payload;
    if (left_tag == 2u)
        return left_payload == right_payload && left_payload < token_capacity &&
            type_generic_param_slot_by_token[left_payload] != INVALID;
    uint capacity = checked_type_capacity();
    if (left_tag != 3u || left_payload >= capacity || right_payload >= capacity) return false;
    return ct_is_resolved(left_id) && left_id == right_id;
}

// Whether two checked references are known to denote one type: the same
// operand, or rows with one canonical ID. Nothing is interned, so a row the
// table does not hold yet equals only itself. For progress checks.
public bool checked_refs_known_equal(uint left_tag, uint left_payload, uint right_tag, uint right_payload)
{
    static const uint INVALID = 0xffffffffu;
    if (left_tag == 0u || left_payload == INVALID) return false;
    if (left_tag == right_tag && left_payload == right_payload) return true;
    if (left_tag != 3u || right_tag != 3u) return false;
    uint left = ct_ref(3u, left_payload);
    return ct_is_resolved(left) && left == ct_ref(3u, right_payload);
}

// How canonical_checked_resolve reads a reference.
// instance_scoped_reference: the reference under nominal `context`.
public static const uint CHECKED_RESOLVE_SCOPED = 0u;
// checked_scoped_reference: a closed row is itself, else as SCOPED.
public static const uint CHECKED_RESOLVE_CHECKED = 1u;
// The reference unchanged, when it is a scalar or a closed row.
public static const uint CHECKED_RESOLVE_CLOSED = 2u;

// One reader for the three modes, so a kernel that needs several of them
// reads each ID at one site. (tag, payload) is a declaration-side reference
// and `context` the nominal application whose arguments bind its parameters
// (INVALID for none). A substituted row is the row of the substitution's ID;
// a reference the environment leaves unchanged keeps its own row.
public bool canonical_checked_resolve<I : ICheckedIds>(uint mode, uint tag, uint payload,
    uint context, uint token_capacity, out uint result_tag, out uint result_payload)
{
    uint capacity = checked_type_capacity();
    bool row = tag == 3u && payload < capacity;
    bool scoped = checked_resolve_scoped(mode, context);
    uint term = CT_UNKNOWN; uint env = CT_UNKNOWN;
    if (row && (mode != CHECKED_RESOLVE_SCOPED || scoped))
        checked_row_ids<I>(payload, scoped ? context : payload, term, env);
    return canonical_checked_resolve_ids(mode, tag, payload, term, context, env, token_capacity,
        result_tag, result_payload);
}

// Whether canonical_checked_resolve reads `context` as an environment.
public bool checked_resolve_scoped(uint mode, uint context)
{
    return mode != CHECKED_RESOLVE_CLOSED && context != 0xffffffffu &&
        (context & 0x80000000u) == 0u && context < checked_type_capacity();
}

// canonical_checked_resolve over IDs the caller read: `term` is the ID of
// row `payload` (when tag is 3) and `env` that of row `context` (when
// checked_resolve_scoped).
public bool canonical_checked_resolve_ids(uint mode, uint tag, uint payload, uint term,
    uint context, uint env, uint token_capacity, out uint result_tag, out uint result_payload)
{
    static const uint INVALID = 0xffffffffu;
    result_tag = 0u; result_payload = INVALID;
    uint capacity = checked_type_capacity();
    bool row = tag == 3u && payload < capacity;
    bool scoped = checked_resolve_scoped(mode, context);
    if (mode == CHECKED_RESOLVE_CLOSED)
    {
        result_tag = tag; result_payload = payload;
        return (tag == 1u && payload != INVALID) || (row && ct_closed(term));
    }
    if (mode == CHECKED_RESOLVE_CHECKED && row && ct_closed(term))
    {
        result_tag = tag; result_payload = payload;
        return true;
    }
    if (context != INVALID && !scoped) return false;
    if (tag == 2u && context != INVALID)
    {
        uint slot = payload < token_capacity ? ScopedCheckedTypeGraph.parameter_slot(payload) : INVALID;
        if (slot == INVALID || !ScopedCheckedTypeGraph.environment_argument(context, slot, tag, payload))
            return false;
        // The argument is already checked in caller scope. Applying the
        // receiver environment again would capture a caller's parameter.
        context = INVALID;
    }
    if ((tag == 1u && payload != 0u && payload != INVALID) ||
        (tag == 2u && payload < token_capacity && ScopedCheckedTypeGraph.parameter_slot(payload) != INVALID))
    {
        result_tag = tag; result_payload = payload;
        return true;
    }
    if (tag != 3u || payload >= capacity) return false;
    uint kind = type_instance_kind[payload];
    if (kind < 1u || kind > 4u) return false;
    if (context != INVALID)
    {
        if (!ct_is_resolved(term)) return false;
        if (!ct_closed(term))
        {
            if (!ct_is_resolved(env)) return false;
            CtSpare spare = ct_spare_none();
            uint id = ct_subst(CheckedSlots(), env, term, false, spare);
            if (!ct_is_record(id)) return false;
            if (id != term)
            {
                uint2 realized = ct_realized_ref(id);
                if (realized.x != 3u || realized.y >= capacity) return false;
                payload = realized.y;
            }
        }
    }
    result_tag = 3u; result_payload = payload;
    return true;
}

// instance_scoped_reference over canonical IDs.
public bool canonical_scoped_reference<I : ICheckedIds>(uint tag, uint payload, uint context,
    uint token_capacity, out uint result_tag, out uint result_payload)
{
    return canonical_checked_resolve<I>(CHECKED_RESOLVE_SCOPED, tag, payload, context, token_capacity,
        result_tag, result_payload);
}

// checked_scoped_reference over canonical IDs: a closed row is its own
// result under any environment.
public bool canonical_checked_scoped_reference<I : ICheckedIds>(uint tag, uint payload, uint context,
    uint token_capacity, out uint result_tag, out uint result_payload)
{
    return canonical_checked_resolve<I>(CHECKED_RESOLVE_CHECKED, tag, payload, context, token_capacity,
        result_tag, result_payload);
}
