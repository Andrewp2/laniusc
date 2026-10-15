// Virtual rows: one checked row per canonical type ID, and one checked
// constant row (atom or projection) per constant ID, so consumers that read
// checked rows keep working while producers compute IDs.
//
// ct_row_of[id] is the row of `id`: a type row, or (kind << 30) | row for a
// constant (kind 1 atom, 3 projection); INVALID when there is none yet, and
// CT_ROW_CLAIMED while one lane writes it. Source rows seed it (01_seed_rows,
// the smallest row of each ID). A missing row is realized bottom-up without
// a stack: a lane descends from the root to the first child without a row,
// claims that ID, writes its row in full from its record, releases it and
// publishes it, then starts again from the root. A lane that meets a claimed
// ID stops with CT_REALIZE_BUSY and retries in a later round, so a row is
// allocated once per ID. A realized row r also gets canonical_row[r] = id, so
// ct_ref reads it as its ID.
//
// Spelling follows the canonical bridge: a named type is spelled by its local
// declaration token when it has one, else by its (library, unit, local)
// triple. Array lengths are count classes: a count is a u32 atom and a
// constant parameter a u32 projection of it, as source arrays are written.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.mutable_checked_type_graph;
import type_checker.constant_atoms;
import type_checker.constant_publication;
import primitive_types;

public RWStructuredBuffer<uint> type_application_count;
public RWStructuredBuffer<uint> type_instance_state;
public RWStructuredBuffer<uint> type_instance_aggregate_word_count;
public RWStructuredBuffer<uint> type_native_word_count;
public RWStructuredBuffer<uint> type_native_scalar_identity;

static const uint INVALID = 0xffffffffu;
// Named metadata field 5: type count, high bit for interleaved domains
// (application_argument_reference.slang).
static const uint INTERLEAVED_DOMAINS = 0x80000000u;
// Private rows own 32 argument words each, after the source rows' four and
// the 64 body rows' 32 (allocate_application.slang).
static const uint PRIVATE_ROW_ARGS = 32u;
static const uint BODY_ROWS = 64u;
static const uint DEPTH_LIMIT = 64u;
static const uint WORK_LIMIT = 1024u;

// Failures, matching the materializer's: 1 capacity, 2 limits, 4 no checked
// spelling (a dependency slot parameter, an unsupported record); 8 another
// lane is writing a row this one needs (retry in a later round).
public static const uint CT_REALIZE_CAPACITY = 1u;
public static const uint CT_REALIZE_LIMIT = 2u;
public static const uint CT_REALIZE_INVALID = 4u;
public static const uint CT_REALIZE_BUSY = 8u;

uint token_rows()
{
    uint count; uint stride;
    type_generic_param_slot_by_token.GetDimensions(count, stride);
    return count;
}

// Reserve a private row with its own argument block, or INVALID.
uint allocate_row(uint arity)
{
    uint ordinal; InterlockedAdd(type_application_count[0u], 1u, ordinal);
    uint base = token_rows() + BODY_ROWS;
    uint capacity = mutable_type_capacity();
    uint args; uint stride;
    type_instance_arg_ref_tag.GetDimensions(args, stride);
    uint arg_start = token_rows() * 4u + BODY_ROWS * PRIVATE_ROW_ARGS + ordinal * PRIVATE_ROW_ARGS;
    if (arity > PRIVATE_ROW_ARGS || base > capacity || ordinal >= capacity - base ||
        arg_start > args || PRIVATE_ROW_ARGS > args - arg_start)
    {
        ct_subst_flag(CT_SUBST_OVERFLOW_ROWS);
        return INVALID;
    }
    uint row = base + ordinal;
    type_instance_arg_start[row] = arg_start;
    type_instance_arg_row_start[row] = INVALID;
    type_instance_state[row] = 1u;
    type_instance_aggregate_word_count[row] = 0u;
    type_native_word_count[row] = INVALID;
    type_native_scalar_identity[row] = 0u;
    return row;
}

// A u32 projection of the constant parameter `token`: a symbolic array length
// keeps its count proof the way source arrays do.
bool count_projection(uint token, out uint row)
{
    uint2 reference;
    if (!reserve_checked_constant_row(row) ||
        !publish_checked_constant_projection_at(row, SCALAR_U32, uint2(2u, token), reference))
    {
        ct_subst_flag(CT_SUBST_OVERFLOW_CONSTANTS);
        return false;
    }
    return true;
}

// Whether every child of record `id` has a checked spelling its row can
// hold. Checked before a row is claimed, so a claim only fails on capacity.
bool children_spellable(uint id)
{
    uint kind = ct_kind(id);
    uint arity = ct_arity(id);
    for (uint index = 0u; index < arity; index++)
    {
        uint2 child = ct_realized_ref(ct_arg(id, index));
        if (child.x == 0u) return false;
        bool constant = (child.x & CT_ROW_CONSTANT_TAG) != 0u;
        if (kind == CC_KIND_CAST && !constant) return false;
        if (kind >= CT_KIND_ARRAY && kind <= CT_KIND_REF && constant != (kind == CT_KIND_ARRAY && index == 1u))
            return false;
    }
    return true;
}

// Write the checked constant row of constant `id`; its word, or INVALID.
uint write_constant(uint id, out uint failure)
{
    failure = CT_REALIZE_CAPACITY;
    uint row;
    if (!reserve_checked_constant_row(row))
    {
        ct_subst_flag(CT_SUBST_OVERFLOW_CONSTANTS);
        return INVALID;
    }
    uint2 reference = uint2(0u, INVALID);
    if (ct_kind(id) == CC_KIND_CAST)
    {
        // A cast is a projection of its symbolic child.
        uint2 child = ct_realized_ref(ct_arg(id, 0u));
        if (!publish_checked_constant_projection_at(row, ct_words(id).x,
                uint2(child.x & ~CT_ROW_CONSTANT_TAG, child.y), reference)) return INVALID;
        if (row < ct_projection_capacity()) canonical_projection[row] = id;
    }
    else
    {
        // A value or a count is an atom.
        uint3 value = ct_kind(id) == CC_KIND_COUNT ? uint3(SCALAR_U32, ct_words(id).x, 0u) : ct_words(id);
        if (!publish_checked_constant_atom_at(row, value, reference)) return INVALID;
        if (row < ct_atom_capacity()) canonical_atom[row] = id;
    }
    failure = 0u;
    return (reference.x << 30u) | row;
}

// Write the checked type row of type `id`; the row, or INVALID.
uint write_type(uint id, out uint failure)
{
    failure = CT_REALIZE_CAPACITY;
    uint kind = ct_kind(id);
    uint arity = ct_arity(id);
    uint row = allocate_row(arity);
    if (row == INVALID) return INVALID;
    uint start = type_instance_arg_start[row];
    type_instance_decl_token[row] = INVALID;
    type_instance_arg_count[row] = 0u;
    type_instance_elem_ref_tag[row] = 0u;
    type_instance_elem_ref_payload[row] = INVALID;
    type_instance_len_kind[row] = 0u;
    type_instance_len_payload[row] = INVALID;
    external_type_library_id[row] = INVALID;
    external_type_unit_id[row] = INVALID;
    external_type_local_index[row] = INVALID;
    for (uint index = 0u; index < arity; index++)
    {
        uint2 child = ct_realized_ref(ct_arg(id, index));
        if (kind == CT_KIND_NAMED)
        {
            type_instance_arg_ref_tag[start + index] = child.x;
            type_instance_arg_ref_payload[start + index] = child.y;
        }
        else if (kind == CT_KIND_ARRAY && index == 1u)
        {
            // A constant parameter length is spelled as a u32 projection.
            if (child.x == (CT_ROW_CONSTANT_TAG | 2u))
            {
                uint projection;
                if (!count_projection(child.y, projection)) return INVALID;
                child = uint2(CT_ROW_CONSTANT_TAG | 3u, projection);
            }
            type_instance_len_kind[row] = child.x & ~CT_ROW_CONSTANT_TAG;
            type_instance_len_payload[row] = child.y;
        }
        else
        {
            type_instance_elem_ref_tag[row] = child.x;
            type_instance_elem_ref_payload[row] = child.y;
        }
    }
    if (kind == CT_KIND_NAMED)
    {
        // Field 5: type count and the interleaved flag; field 6: the
        // constant-operand mask (as ct_bridge_metadata reads them).
        uint2 extra = ct_extra[id];
        uint types = ct_type_slots(id);
        uint operands = arity >= 32u ? 0xffffffffu : (1u << arity) - 1u;
        uint tail = types >= 32u ? 0u : operands & ~((1u << types) - 1u);
        uint3 words = ct_words(id);
        type_instance_decl_token[row] = extra.x;
        type_instance_arg_count[row] = arity;
        type_instance_len_kind[row] = types | (extra.y != tail ? INTERLEAVED_DOMAINS : 0u);
        type_instance_len_payload[row] = extra.y;
        if (extra.x == INVALID)
        {
            external_type_library_id[row] = words.x;
            external_type_unit_id[row] = words.y;
            external_type_local_index[row] = words.z;
        }
    }
    // The kind is written last: a row is complete once it has one.
    type_instance_kind[row] = kind - (CT_KIND_NAMED - 1u);
    if (row < ct_row_capacity()) canonical_row[row] = id;
    failure = 0u;
    return row;
}

// Claim, write and publish the row of `id`, whose children all have rows.
// Returns 0 on success, else a CT_REALIZE_* failure.
uint realize_record(uint id)
{
    if (!children_spellable(id)) return CT_REALIZE_INVALID;
    uint previous;
    InterlockedCompareExchange(ct_row_of[id], CT_ROW_INVALID, CT_ROW_CLAIMED, previous);
    if (previous != CT_ROW_INVALID) return previous == CT_ROW_CLAIMED ? CT_REALIZE_BUSY : 0u;
    uint failure;
    uint word = ct_kind(id) >= CC_KIND_VALUE ? write_constant(id, failure) : write_type(id, failure);
    // Release: the row is complete before its publication. A failed claim
    // is given back, so a later round can retry it.
    DeviceMemoryBarrier();
    uint ignored;
    InterlockedCompareExchange(ct_row_of[id], CT_ROW_CLAIMED, word == INVALID ? CT_ROW_INVALID : word, ignored);
    return failure;
}

// The first child of `node` that still needs a row; CT_NONE when it has
// none, CT_UNKNOWN when a child has no checked spelling.
uint pending_child(uint node)
{
    uint arity = ct_arity(node);
    for (uint index = 0u; index < arity; index++)
    {
        uint child = ct_arg(node, index);
        uint2 operand = ct_realized_ref(child);
        if (operand.x != 0u) continue;
        return operand.y == CT_ROW_PENDING ? child : CT_UNKNOWN;
    }
    return CT_NONE;
}

// The checked operand of canonical reference `id` (constants with
// CT_ROW_CONSTANT_TAG | kind), realizing the rows it lacks. `failure` is set
// when there is none: CT_REALIZE_BUSY asks for a later round.
public uint2 ct_realize(uint id, out uint failure)
{
    failure = 0u;
    uint2 result = ct_realized_ref(id);
    if (result.x != 0u) return result;
    if (result.y != CT_ROW_PENDING || id >= ct_row_of_capacity())
    {
        failure = CT_REALIZE_INVALID;
        return uint2(0u, INVALID);
    }
    for (uint work = 0u; work < WORK_LIMIT; work++)
    {
        // Descend to a record whose children all have rows. Each step is a
        // call result, so the loop carries one value.
        uint target = id;
        uint child = pending_child(target);
        for (uint depth = 0u; depth < DEPTH_LIMIT && ct_is_record(child); depth++)
        {
            target = child;
            child = pending_child(target);
        }
        if (child == CT_UNKNOWN)
        {
            failure = CT_REALIZE_INVALID;
            return uint2(0u, INVALID);
        }
        if (child != CT_NONE) break;
        failure = realize_record(target);
        if (failure != 0u) return uint2(0u, INVALID);
        if (target == id) return ct_realized_ref(id);
    }
    failure = CT_REALIZE_LIMIT;
    return uint2(0u, INVALID);
}
