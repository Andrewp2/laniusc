// Retain substituted record fields and every enum variant's payload group of
// imported applications, over canonical IDs. Each lane owns one application
// row: its ID is the environment of the declaration's field and payload
// patterns (ct_subst), and each result is realized as a checked row
// (ct_realize) and published as a checked reference. Published references
// and group boundaries remain meaningful after this immutable dependency
// page has been replaced.
import semantic_interface_layout;
import dependency_interface;
import atomics;
import status;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.ct_checked;
import type_checker.substitution.source_slots;
#include "../type/instances/live_type_rows.slang"

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> imported_field_ref_start;
RWStructuredBuffer<uint> imported_field_ref_count;
RWStructuredBuffer<uint> imported_field_ref_tag;
RWStructuredBuffer<uint> imported_field_ref_payload;
RWStructuredBuffer<uint2> imported_field_name_hash;
RWStructuredBuffer<uint> imported_field_ref_total;
RWStructuredBuffer<uint> imported_layout_kind;
RWStructuredBuffer<uint> imported_layout_group_start;
RWStructuredBuffer<uint> imported_layout_group_count;
RWStructuredBuffer<uint2> imported_layout_groups;
RWStructuredBuffer<uint> imported_layout_group_total;
// [defer missing bindings, number of newly published type facts].
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;
StructuredBuffer<uint> token_count;

static const uint INVALID = 0xffffffffu;

// The canonical type of dependency node `t` of the resident page (its alias
// root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? ct_dependency_state(root) : CT_UNKNOWN;
}

// A variant's payloads are its constructor signature's parameters: edges
// [start, start + count) of the signature node.
bool variant_payloads(uint member, out uint start, out uint count)
{
    start = 0u; count = 0u;
    uint type = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
    uint types = dependency_type_count();
    uint signature = type < types ? canonical_type_roots[type] : INVALID;
    if (signature >= types || dependency_type_word(signature * 9u) != 7u) return false;
    start = dependency_type_word(signature * 9u + 3u);
    uint edges = dependency_type_word(signature * 9u + 4u);
    uint capacity = dependency_count(5u);
    if (edges == 0u || start > capacity || edges > capacity - start) return false;
    count = edges - 1u;
    return true;
}

// Publish field `target` of application `id` (row `instance`): dependency node `type`
// substituted under the application. False when it has no checked row yet;
// `busy` when another lane is writing a row it needs.
bool publish_field(uint id, uint instance, uint target, uint type, inout CtSpare spare, inout bool busy)
{
    uint pattern = dependency_type(type);
    uint field = ct_is_resolved(pattern) ? ct_subst(SourceSlots(), id, pattern, true, spare) : CT_UNKNOWN;
    uint failure = CT_REALIZE_INVALID;
    uint2 reference = uint2(0u, INVALID);
    if (ct_is_resolved(field)) reference = ct_realize(field, failure);
    if (failure == CT_REALIZE_BUSY) busy = true;
    // The private row arena or the constant rows are full: fail closed.
    if (failure == CT_REALIZE_CAPACITY)
        record_min_token_error(status, min(instance, gParams.n_tokens - 1u), 6u, 0x474e0001u);
    bool resolved = failure == 0u && (reference.x == 1u || reference.x == 2u || reference.x == 3u) &&
        reference.y != INVALID;
    if (!resolved) reference = uint2(0u, INVALID);
    imported_field_ref_tag[target] = reference.x;
    imported_field_ref_payload[target] = reference.y;
    return resolved;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint lanes = live_type_row_lanes(gParams.n_tokens, token_count[0u]);
    if (lane >= lanes) return;
    uint capacity; uint stride; uint group_capacity;
    imported_field_ref_tag.GetDimensions(capacity, stride);
    imported_layout_groups.GetDimensions(group_capacity, stride);
    uint row_spare = CT_NONE;
    CtSpare spare = ct_spare_none();
    bool busy = false;
    // The job's live rows (live_type_rows.slang). Rows realized while this
    // dispatch runs extend them; the count is read again for each row.
    uint source_rows;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    for (uint index = lane; index < live_type_row_count(gParams.n_tokens, source_rows,
        mutable_type_capacity(), type_application_count[0u]); index += lanes)
    {
        uint instance = live_type_row(index, gParams.n_tokens, source_rows);
        if (type_instance_kind[instance] != 1u || type_instance_decl_token[instance] != INVALID ||
            external_type_library_id[instance] == INVALID) continue;
        uint declaration = dependency_find_declaration(external_type_library_id[instance],
            external_type_unit_id[instance], external_type_local_index[instance]);
        if (declaration >= dependency_declaration_count()) continue;
        uint kind = dependency_declaration_word(declaration * 14u + 6u);
        if (kind != 6u && kind != 7u) continue;
        uint start = dependency_declaration_word(declaration * 14u + 8u);
        uint count = dependency_declaration_word(declaration * 14u + 9u);
        if (start > dependency_member_count() || count > dependency_member_count() - start) continue;
        uint fields = 0u; uint groups = kind == 6u ? 1u : 0u;
        bool complete = true;
        for (uint member = start; member < start + count; member++)
        {
            uint member_kind = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u);
            if (kind == 6u && member_kind == 4u) fields++;
            if (kind == 7u && member_kind == 5u)
            {
                uint payload_start; uint payload_count;
                if (!variant_payloads(member, payload_start, payload_count) ||
                    payload_count > capacity || fields > capacity - payload_count)
                { complete = false; break; }
                groups++; fields += payload_count;
            }
        }
        uint previous_kind = imported_layout_kind[instance];
        imported_layout_kind[instance] = 0u;
        if (!complete)
        { record_min_token_error(status, min(instance, gParams.n_tokens - 1u), 6u, 0x474e0001u); return; }
        uint target = imported_field_ref_start[instance];
        bool new_fields = target == INVALID || imported_field_ref_count[instance] != fields;
        if (new_fields) target = atomic_u32_add(imported_field_ref_total, 0u, fields);
        uint group_target = imported_layout_group_start[instance];
        bool new_groups = group_target == INVALID || imported_layout_group_count[instance] != groups;
        if (new_groups) group_target = atomic_u32_add(imported_layout_group_total, 0u, groups);
        if (target > capacity || fields > capacity - target ||
            group_target > group_capacity || groups > group_capacity - group_target)
        { record_min_token_error(status, min(instance, gParams.n_tokens - 1u), 6u, 0x474e0001u); return; }
        imported_field_ref_start[instance] = target;
        imported_field_ref_count[instance] = fields;
        imported_layout_group_start[instance] = group_target;
        imported_layout_group_count[instance] = groups;
        // Completion is monotone within a checked application. Equivalent
        // index representatives can differ without creating new layout work.
        bool changed = previous_kind != (kind | 0x80000000u) || new_fields || new_groups;
        // Field names and individual checked references are useful before all
        // payloads are ready. Complete native layouts have a separate state bit.
        imported_layout_kind[instance] = kind;
        // The application's own ID: source rows and realized rows have one;
        // rows generated during inference are interned here.
        uint id = ct_intern_checked<CtMutableRows>(3u, instance, row_spare);
        bool named = ct_is_record(id) && ct_kind(id) == CT_KIND_NAMED;
        uint ordinal = 0u; uint group = 0u;
        if (kind == 6u) imported_layout_groups[group_target] = uint2(0u, fields);
        for (uint member = start; member < start + count; member++)
        {
            uint member_kind = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u);
            uint type = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
            uint payload_start = 0u; uint payload_count = 0u;
            if (kind == 6u && member_kind == 4u)
                payload_count = 1u;
            else if (kind == 7u && member_kind == 5u)
            {
                variant_payloads(member, payload_start, payload_count);
                imported_layout_groups[group_target + group++] = uint2(ordinal, payload_count);
            }
            for (uint payload = 0u; payload < payload_count; payload++)
            {
                uint child = kind == 6u ? type : dependency_type_edge_word(payload_start + payload);
                imported_field_name_hash[target + ordinal] = kind == 6u
                    ? uint2(dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 3u),
                            dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 4u))
                    : uint2(0u, 0u);
                bool resolved = false;
                if (named) resolved = publish_field(id, instance, target + ordinal, child, spare, busy);
                else
                {
                    imported_field_ref_tag[target + ordinal] = 0u;
                    imported_field_ref_payload[target + ordinal] = INVALID;
                }
                ordinal++;
                complete = complete && resolved;
            }
        }
        if (complete)
        {
            imported_layout_kind[instance] = kind | 0x80000000u;
            if (changed) atomic_u32_add(call_inference_state, 1u, 1u);
        }
    }
    // Another lane was writing a row a field needs: run another round.
    if (busy) atomic_u32_add(call_inference_state, 1u, 1u);
}
