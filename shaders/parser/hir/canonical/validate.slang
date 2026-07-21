struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirRange { uint start; uint count; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };
struct HirGenericParam { uint owner; uint name_token; uint kind; uint file_id; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
struct HirMatchPayload { uint arm; uint pattern; uint ordinal; uint file_id; };
struct HirArrayElement { uint array; uint value; uint ordinal; uint file_id; };
struct HirString { uint node; uint data_offset; uint decoded_len; uint file_id; };
struct HirMethodCore { uint node; uint owner; uint impl_node; uint name_token; };
struct HirMethodSignature { uint first_param_token; uint impl_receiver_type; uint receiver_mode; uint metadata; };
struct HirPredicate { uint owner; uint subject; uint bound; uint metadata; };

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<HirCore> hir_core;
StructuredBuffer<HirLinks> hir_links;
StructuredBuffer<HirPayload> hir_payload;
StructuredBuffer<uint> hir_call_arg_table_count;
StructuredBuffer<HirCallArg> hir_call_args;
StructuredBuffer<uint> hir_param_table_count;
StructuredBuffer<HirParam> hir_params;
StructuredBuffer<HirRange> hir_param_ranges;
StructuredBuffer<uint> hir_type_arg_table_count;
StructuredBuffer<HirTypeArg> hir_type_args;
StructuredBuffer<HirRange> hir_type_arg_ranges;
StructuredBuffer<uint> hir_generic_param_table_count;
StructuredBuffer<HirGenericParam> hir_generic_params;
StructuredBuffer<HirRange> hir_generic_param_ranges;
StructuredBuffer<uint> hir_path_table_count;
StructuredBuffer<HirPath> hir_paths;
StructuredBuffer<uint> hir_path_segment_table_count;
StructuredBuffer<HirPathSegment> hir_path_segments;
StructuredBuffer<uint> hir_field_table_count;
StructuredBuffer<HirField> hir_fields;
StructuredBuffer<uint> hir_variant_table_count;
StructuredBuffer<HirVariant> hir_variants;
StructuredBuffer<uint> hir_variant_payload_start;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> hir_variant_payload_table_count;
StructuredBuffer<HirVariantPayload> hir_variant_payloads;
StructuredBuffer<uint> hir_match_arm_table_count;
StructuredBuffer<HirMatchArm> hir_match_arms;
StructuredBuffer<uint> hir_match_payload_start;
StructuredBuffer<uint> hir_match_payload_count;
StructuredBuffer<uint> hir_match_payload_table_count;
StructuredBuffer<HirMatchPayload> hir_match_payloads;
StructuredBuffer<uint> hir_array_element_start;
StructuredBuffer<uint> hir_array_element_count;
StructuredBuffer<uint> hir_array_element_table_count;
StructuredBuffer<HirArrayElement> hir_array_elements;
StructuredBuffer<uint> hir_string_count;
StructuredBuffer<HirString> hir_strings;
StructuredBuffer<uint> hir_string_pool_len;
StructuredBuffer<uint> hir_method_count;
StructuredBuffer<HirMethodCore> hir_method_cores;
StructuredBuffer<HirMethodSignature> hir_method_signatures;
StructuredBuffer<uint> hir_predicate_count;
StructuredBuffer<HirPredicate> hir_predicates;
StructuredBuffer<uint> hir_expr_parent;
StructuredBuffer<uint> hir_expr_root;
StructuredBuffer<uint> hir_expr_forest_status;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_MEMBER_EXPR = 21u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    uint call_arg_count = min(hir_call_arg_table_count[0u], gCanonical.canonical_capacity);
    uint param_count = min(hir_param_table_count[0u], gCanonical.canonical_capacity);
    uint type_arg_count = min(hir_type_arg_table_count[0u], gCanonical.canonical_capacity);
    uint generic_param_count = min(hir_generic_param_table_count[0u], gCanonical.canonical_capacity);
    uint path_count = min(hir_path_table_count[0u], gCanonical.canonical_capacity);
    uint path_segment_count = min(hir_path_segment_table_count[0u], gCanonical.canonical_capacity);
    uint field_count = min(hir_field_table_count[0u], gCanonical.canonical_capacity);
    uint variant_count = min(hir_variant_table_count[0u], gCanonical.canonical_capacity);
    uint variant_payload_count = min(hir_variant_payload_table_count[0u], gCanonical.canonical_capacity);
    uint match_arm_count = min(hir_match_arm_table_count[0u], gCanonical.canonical_capacity);
    uint match_payload_count = min(hir_match_payload_table_count[0u], gCanonical.canonical_capacity);
    uint array_element_count = min(hir_array_element_table_count[0u], gCanonical.canonical_capacity);
    uint string_count = min(hir_string_count[0u], gCanonical.canonical_capacity);
    uint method_count = min(hir_method_count[0u], gCanonical.canonical_capacity);
    uint predicate_count = min(hir_predicate_count[0u], gCanonical.canonical_capacity);
    uint arg_reason = 0u;
    if (row < call_arg_count)
    {
        HirCallArg arg = hir_call_args[row];
        if (arg.call >= count) arg_reason |= 32u;
        if (arg.value >= count) arg_reason |= 64u;
        if (arg_reason == 0u)
        {
            HirPayload call_payload = hir_payload[arg.call];
            if (arg.ordinal >= call_payload.c) arg_reason |= 128u;
            if (call_payload.b + arg.ordinal != row) arg_reason |= 256u;
        }
    }
    uint param_reason = 0u;
    if (row < param_count)
    {
        HirParam parameter = hir_params[row];
        if (parameter.owner >= count || hir_core[parameter.owner].kind != 3u)
            param_reason |= 512u;
        if (parameter.name_token >= gCanonical.canonical_capacity)
            param_reason |= 1024u;
        if (parameter.type_node != INVALID && parameter.type_node >= count)
            param_reason |= 2048u;
        if (parameter.owner < count)
        {
            HirRange range = hir_param_ranges[parameter.owner];
            if (range.start == INVALID || row < range.start || row - range.start >= range.count)
                param_reason |= 4096u;
            if (parameter.ordinal == 0u && range.start != row)
                param_reason |= 4096u;
        }
        if (parameter.ordinal > 0u)
        {
            if (row == 0u)
                param_reason |= 4096u;
            else
            {
                HirParam previous = hir_params[row - 1u];
                if (previous.owner != parameter.owner || previous.ordinal + 1u != parameter.ordinal)
                    param_reason |= 4096u;
            }
        }
    }
    uint type_arg_reason = 0u;
    if (row < type_arg_count)
    {
        HirTypeArg type_arg = hir_type_args[row];
        if (type_arg.owner >= count || hir_core[type_arg.owner].kind != 5u)
            type_arg_reason |= 8192u;
        if (type_arg.value >= count || hir_core[type_arg.value].kind != 5u)
            type_arg_reason |= 16384u;
        if (type_arg.owner < count)
        {
            HirRange range = hir_type_arg_ranges[type_arg.owner];
            if (range.start == INVALID || row < range.start || row - range.start >= range.count)
                type_arg_reason |= 32768u;
            if (type_arg.ordinal == 0u && range.start != row)
                type_arg_reason |= 32768u;
        }
        if (type_arg.ordinal > 0u)
        {
            if (row == 0u)
                type_arg_reason |= 32768u;
            else
            {
                HirTypeArg previous = hir_type_args[row - 1u];
                if (previous.owner != type_arg.owner || previous.ordinal + 1u != type_arg.ordinal)
                    type_arg_reason |= 32768u;
            }
        }
    }
    uint generic_param_reason = 0u;
    if (row < generic_param_count)
    {
        HirGenericParam parameter = hir_generic_params[row];
        if (parameter.owner >= count) generic_param_reason |= 65536u;
        if (parameter.name_token >= gCanonical.canonical_capacity) generic_param_reason |= 131072u;
        if (parameter.kind != 1u && parameter.kind != 2u) generic_param_reason |= 262144u;
        if (parameter.owner < count)
        {
            HirRange range = hir_generic_param_ranges[parameter.owner];
            if (range.start == INVALID || row < range.start || row - range.start >= range.count)
                generic_param_reason |= 524288u;
        }
    }
    uint path_reason = 0u;
    if (row < path_count)
    {
        HirPath path = hir_paths[row];
        if (path.owner >= count) path_reason |= 524288u;
        if (path.segment_count == 0u || path.segment_start >= path_segment_count ||
            path.segment_count > path_segment_count - path.segment_start)
            path_reason |= 1048576u;
        if (path.kind < 1u || path.kind > 5u)
            path_reason |= 1048576u;
    }
    uint path_segment_reason = 0u;
    if (row < path_segment_count)
    {
        HirPathSegment segment = hir_path_segments[row];
        if (segment.path >= path_count) path_segment_reason |= 2097152u;
        if (segment.name_token >= gCanonical.canonical_capacity) path_segment_reason |= 4194304u;
        if (segment.path < path_count)
        {
            HirPath path = hir_paths[segment.path];
            if (path.segment_start + segment.ordinal != row || segment.ordinal >= path.segment_count)
                path_segment_reason |= 8388608u;
        }
    }
    uint field_reason = 0u;
    if (row < field_count)
    {
        HirField field = hir_fields[row];
        if (field.owner >= count) field_reason |= 16777216u;
        if (field.name_token >= gCanonical.canonical_capacity) field_reason |= 33554432u;
        if (field.value >= count) field_reason |= 67108864u;
        if (field.owner < count)
        {
            uint owner_kind = hir_core[field.owner].kind;
            if (field.value >= count && owner_kind == 27u) field_reason |= 1073741824u;
            if (field.value >= count && owner_kind == 28u) field_reason |= 2147483648u;
            if (owner_kind != 27u && owner_kind != 28u) field_reason |= 134217728u;
            if (owner_kind == 27u && field.value < count && hir_core[field.value].kind != 5u)
                field_reason |= 268435456u;
            if (owner_kind == 28u)
            {
                HirPayload owner_payload = hir_payload[field.owner];
                if (owner_payload.b == INVALID || field.ordinal >= owner_payload.c ||
                    owner_payload.b + field.ordinal != row)
                    field_reason |= 536870912u;
                bool last_field = row + 1u == field_count ||
                    hir_fields[row + 1u].owner != field.owner;
                if (last_field && owner_payload.c != field.ordinal + 1u)
                    field_reason |= 536870912u;
            }
        }
        if (field.ordinal > 0u)
        {
            if (row == 0u)
                field_reason |= 536870912u;
            else
            {
                HirField previous = hir_fields[row - 1u];
                if (previous.owner != field.owner || previous.ordinal + 1u != field.ordinal)
                    field_reason |= 536870912u;
            }
        }
    }
    uint variant_reason = 0u;
    if (row < variant_count)
    {
        HirVariant variant = hir_variants[row];
        if (variant.owner >= count || hir_core[variant.owner].kind != 26u) variant_reason |= 32u;
        if (variant.name_token >= gCanonical.canonical_capacity) variant_reason |= 64u;
        if (variant.ordinal > 0u)
        {
            if (row == 0u)
                variant_reason |= 128u;
            else
            {
                HirVariant previous = hir_variants[row - 1u];
                if (previous.owner != variant.owner || previous.ordinal + 1u != variant.ordinal)
                    variant_reason |= 128u;
            }
        }
        uint payload_start = hir_variant_payload_start[row];
        uint payload_count = hir_variant_payload_count[row];
        if (payload_count == 0u)
        {
            if (payload_start != INVALID) variant_reason |= 256u;
        }
        else if (payload_start >= variant_payload_count ||
                 payload_count > variant_payload_count - payload_start)
            variant_reason |= 256u;
    }
    uint variant_payload_reason = 0u;
    if (row < variant_payload_count)
    {
        HirVariantPayload payload = hir_variant_payloads[row];
        if (payload.variant >= variant_count) variant_payload_reason |= 512u;
        if (payload.type_node >= count || hir_core[payload.type_node].kind != 5u)
            variant_payload_reason |= 1024u;
        if (payload.variant < variant_count)
        {
            uint start = hir_variant_payload_start[payload.variant];
            uint family_count = hir_variant_payload_count[payload.variant];
            if (start == INVALID || payload.ordinal >= family_count || start + payload.ordinal != row)
                variant_payload_reason |= 2048u;
        }
    }
    uint match_arm_reason = 0u;
    if (row < match_arm_count)
    {
        HirMatchArm arm = hir_match_arms[row];
        if (arm.owner >= count || hir_core[arm.owner].kind != 34u) match_arm_reason |= 4096u;
        if (arm.pattern >= count) match_arm_reason |= 8192u;
        if (arm.result >= count) match_arm_reason |= 16384u;
        if (arm.owner < count)
        {
            HirPayload owner_payload = hir_payload[arm.owner];
            if (owner_payload.b == INVALID || arm.ordinal >= owner_payload.c ||
                owner_payload.b + arm.ordinal != row)
                match_arm_reason |= 32768u;
            bool last_arm = row + 1u == match_arm_count ||
                hir_match_arms[row + 1u].owner != arm.owner;
            if (last_arm && owner_payload.c != arm.ordinal + 1u)
                match_arm_reason |= 32768u;
        }
        if (arm.ordinal > 0u)
        {
            if (row == 0u)
                match_arm_reason |= 32768u;
            else
            {
                HirMatchArm previous = hir_match_arms[row - 1u];
                if (previous.owner != arm.owner || previous.ordinal + 1u != arm.ordinal)
                    match_arm_reason |= 32768u;
            }
        }
        uint payload_start = hir_match_payload_start[row];
        uint payload_count = hir_match_payload_count[row];
        if (payload_count == 0u)
        {
            if (payload_start != INVALID) match_arm_reason |= 65536u;
        }
        else if (payload_start >= match_payload_count ||
                 payload_count > match_payload_count - payload_start)
            match_arm_reason |= 65536u;
    }
    uint match_payload_reason = 0u;
    if (row < match_payload_count)
    {
        HirMatchPayload payload = hir_match_payloads[row];
        if (payload.arm >= match_arm_count) match_payload_reason |= 131072u;
        if (payload.pattern >= count) match_payload_reason |= 262144u;
        if (payload.arm < match_arm_count)
        {
            uint start = hir_match_payload_start[payload.arm];
            uint family_count = hir_match_payload_count[payload.arm];
            if (start == INVALID || payload.ordinal >= family_count || start + payload.ordinal != row)
                match_payload_reason |= 524288u;
        }
    }
    uint array_element_reason = 0u;
    if (row < array_element_count)
    {
        HirArrayElement element = hir_array_elements[row];
        if (element.array >= count || hir_core[element.array].kind != 24u)
            array_element_reason |= 1048576u;
        if (element.value >= count) array_element_reason |= 2097152u;
        if (element.array < count)
        {
            uint start = hir_array_element_start[element.array];
            uint family_count = hir_array_element_count[element.array];
            if (start == INVALID || element.ordinal >= family_count || start + element.ordinal != row)
                array_element_reason |= 4194304u;
        }
    }
    uint string_reason = 0u;
    if (row < string_count)
    {
        HirString string_row = hir_strings[row];
        if (string_row.node >= count || hir_core[string_row.node].kind != 23u)
            string_reason |= 8388608u;
        else if (hir_payload[string_row.node].b != row)
            string_reason |= 8388608u;
        uint pool_len = hir_string_pool_len[0u];
        if (string_row.data_offset > pool_len || string_row.decoded_len > pool_len - string_row.data_offset)
            string_reason |= 16777216u;
        if (string_row.node < count && string_row.file_id != hir_links[string_row.node].file_id)
            string_reason |= 33554432u;
    }
    uint method_reason = 0u;
    if (row < method_count)
    {
        HirMethodCore method = hir_method_cores[row];
        HirMethodSignature signature = hir_method_signatures[row];
        if (method.node >= count || hir_core[method.node].kind != 3u) method_reason |= 67108864u;
        if (row != 0u && hir_method_cores[row - 1u].node >= method.node)
            method_reason |= 67108864u;
        if (method.owner >= count) method_reason |= 134217728u;
        if (method.impl_node != INVALID &&
            (method.impl_node >= count || hir_core[method.impl_node].kind != 35u))
            method_reason |= 268435456u;
        if (method.name_token >= gCanonical.canonical_capacity) method_reason |= 536870912u;
        if (signature.first_param_token != INVALID &&
            signature.first_param_token >= gCanonical.canonical_capacity)
            method_reason |= 1073741824u;
        if (signature.impl_receiver_type != INVALID &&
            (signature.impl_receiver_type >= count || hir_core[signature.impl_receiver_type].kind != 5u))
            method_reason |= 2147483648u;
    }
    uint predicate_reason = 0u;
    if (row < predicate_count)
    {
        HirPredicate predicate = hir_predicates[row];
        uint kind = predicate.metadata & 0xffu;
        uint file_id = predicate.metadata >> 8u;
        if (predicate.owner >= count) predicate_reason |= 32u;
        if (predicate.bound >= count || hir_core[predicate.bound].kind != 5u)
            predicate_reason |= 64u;
        if (kind == 1u)
        {
            if (predicate.subject >= gCanonical.canonical_capacity) predicate_reason |= 128u;
            if (predicate.bound < count && hir_core[predicate.bound].parent != predicate.owner)
                predicate_reason |= 256u;
        }
        else if (kind == 2u)
        {
            if (predicate.owner >= count || hir_core[predicate.owner].kind != 35u)
                predicate_reason |= 512u;
            if (predicate.subject >= count || hir_core[predicate.subject].kind != 5u)
                predicate_reason |= 1024u;
        }
        else predicate_reason |= 2048u;
        if (predicate.owner < count && file_id != hir_links[predicate.owner].file_id)
            predicate_reason |= 4096u;
    }
    if (row >= count)
    {
        if (arg_reason != 0u || param_reason != 0u || type_arg_reason != 0u ||
            generic_param_reason != 0u || path_reason != 0u || path_segment_reason != 0u ||
            field_reason != 0u || variant_reason != 0u || variant_payload_reason != 0u ||
            match_arm_reason != 0u || match_payload_reason != 0u ||
            array_element_reason != 0u || string_reason != 0u || method_reason != 0u ||
            predicate_reason != 0u)
        {
            uint ignored;
            InterlockedMax(canonical_status[0u], 2u, ignored);
            InterlockedMax(canonical_status[3u], row + 1u, ignored);
            InterlockedOr(canonical_status[8u], arg_reason | param_reason | type_arg_reason |
                          generic_param_reason | path_reason | path_segment_reason, ignored);
            InterlockedOr(canonical_status[8u], field_reason, ignored);
            InterlockedOr(canonical_status[8u], variant_reason | variant_payload_reason, ignored);
            InterlockedOr(canonical_status[8u], match_arm_reason | match_payload_reason, ignored);
            InterlockedOr(canonical_status[8u], array_element_reason, ignored);
            InterlockedOr(canonical_status[8u], string_reason, ignored);
            InterlockedOr(canonical_status[8u], method_reason, ignored);
            InterlockedOr(canonical_status[8u], predicate_reason, ignored);
        }
        return;
    }
    HirCore core = hir_core[row];
    HirLinks links = hir_links[row];
    HirPayload payload = hir_payload[row];
    bool parent_ok = core.parent == INVALID || core.parent < row;
    bool span_ok = core.token_start < gCanonical.canonical_capacity &&
                   core.token_end != INVALID && core.token_end >= core.token_start;
    bool subtree_ok = links.subtree_end > row && links.subtree_end <= count;
    bool child_ok = links.first_child == INVALID ||
                    (links.first_child == row + 1u && links.first_child < count &&
                     hir_core[links.first_child].parent == row);
    bool sibling_ok = links.next_sibling == INVALID ||
                      (links.next_sibling > row && links.next_sibling < count &&
                       hir_core[links.next_sibling].parent == core.parent);
    bool payload_ok = core.kind != HIR_MEMBER_EXPR ||
                      (payload.b < count && payload.b != row);
    uint expr_parent = hir_expr_parent[row];
    uint expr_root = hir_expr_root[row];
    bool expr_parent_ok = expr_parent == INVALID ||
                          (expr_parent < count && expr_parent != row);
    bool expr_root_ok = expr_root < count &&
                        (expr_parent == INVALID ? expr_root == row
                                                : hir_expr_root[expr_parent] == expr_root);
    bool expr_forest_ok = row != 0u || hir_expr_forest_status[0u] == 0u;
    uint reason = (parent_ok ? 0u : 1u) | (span_ok ? 0u : 2u) |
                  (subtree_ok ? 0u : 4u) | (child_ok ? 0u : 8u) |
                  (sibling_ok ? 0u : 16u) | (payload_ok ? 0u : 32u) |
                  (expr_parent_ok ? 0u : 64u) | (expr_root_ok ? 0u : 128u) |
                  (expr_forest_ok ? 0u : 256u) |
                  arg_reason | param_reason | type_arg_reason |
                  generic_param_reason | path_reason | path_segment_reason;
    reason |= field_reason;
    reason |= variant_reason | variant_payload_reason;
    reason |= match_arm_reason | match_payload_reason;
    reason |= array_element_reason;
    reason |= string_reason;
    reason |= method_reason;
    reason |= predicate_reason;
    if (reason != 0u)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 2u, ignored);
        InterlockedMax(canonical_status[3u], row + 1u, ignored);
        InterlockedOr(canonical_status[8u], reason, ignored);
    }
}
