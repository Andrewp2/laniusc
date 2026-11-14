// Execution side tables (instance_exec.slang): one lane per virtual slot,
// for every side table whose virtual block reaches it. Each copied record
// names the copy's rows, tokens and table indices. A parameter's checked
// type is its type row's realized reference (as 00_project reads it); a
// field keeps its declaration ordinal; a match arm's payload range moves
// with the payload block.
import hir_records;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

RWStructuredBuffer<HirCallArg> compact_call_args;
RWStructuredBuffer<HirField> compact_fields;
RWStructuredBuffer<HirMatchArm> compact_match_arms;
RWStructuredBuffer<HirMatchPayload> compact_match_payloads;
RWStructuredBuffer<HirArrayElement> compact_array_elements;
RWStructuredBuffer<HirString> compact_strings;
RWStructuredBuffer<HirParam> compact_params;
RWStructuredBuffer<uint> compact_match_payload_start;
RWStructuredBuffer<uint> compact_match_payload_count;
RWStructuredBuffer<uint> struct_init_field_ordinal_by_row;
RWStructuredBuffer<uint> semantic_param_ref_tag_by_row;
RWStructuredBuffer<uint> semantic_param_ref_payload_by_row;

void copy_slot(uint k, uint lane)
{
    if (lane >= instance_exec_counts[EX_COUNT_TABLE + k]) return;
    uint index = instance_exec_counts[EX_COUNT_TABLE_BASE + k] + lane;
    uint entry = ex_entry_of_index(k, index);
    if (entry == EX_INVALID) return;
    ExecMap map = ex_map(entry);
    uint source = ex_tstart(map, k) + (index - ex_vstart(map, k));
    if (k == EX_TABLE_CALL_ARGS)
    {
        HirCallArg value = compact_call_args[source];
        value.call = ex_row(map, value.call);
        value.value = ex_row(map, value.value);
        compact_call_args[index] = value;
    }
    else if (k == EX_TABLE_FIELDS)
    {
        HirField value = compact_fields[source];
        value.owner = ex_row(map, value.owner);
        value.name_token = ex_token(map, value.name_token);
        value.value = ex_row(map, value.value);
        compact_fields[index] = value;
        struct_init_field_ordinal_by_row[index] = struct_init_field_ordinal_by_row[source];
    }
    else if (k == EX_TABLE_MATCH_ARMS)
    {
        HirMatchArm value = compact_match_arms[source];
        value.owner = ex_row(map, value.owner);
        value.pattern = ex_row(map, value.pattern);
        value.result = ex_row(map, value.result);
        compact_match_arms[index] = value;
        uint payloads = compact_match_payload_count[source];
        uint start = compact_match_payload_start[source];
        compact_match_payload_start[index] = payloads != 0u
            ? ex_index(map, EX_TABLE_MATCH_PAYLOADS, start) : start;
        compact_match_payload_count[index] = payloads;
    }
    else if (k == EX_TABLE_MATCH_PAYLOADS)
    {
        HirMatchPayload value = compact_match_payloads[source];
        value.arm = ex_index(map, EX_TABLE_MATCH_ARMS, value.arm);
        value.pattern = ex_row(map, value.pattern);
        value.parent_pattern = ex_row(map, value.parent_pattern);
        compact_match_payloads[index] = value;
    }
    else if (k == EX_TABLE_ARRAY_ELEMENTS)
    {
        HirArrayElement value = compact_array_elements[source];
        value.array = ex_row(map, value.array);
        value.value = ex_row(map, value.value);
        compact_array_elements[index] = value;
    }
    else if (k == EX_TABLE_STRINGS)
    {
        HirString value = compact_strings[source];
        value.node = ex_row(map, value.node);
        compact_strings[index] = value;
    }
    else
    {
        HirParam value = compact_params[source];
        uint type_row = value.type_node;
        value.owner = ex_row(map, value.owner);
        value.name_token = ex_token(map, value.name_token);
        value.type_node = ex_row(map, value.type_node);
        compact_params[index] = value;
        uint2 reference = ex_row_ref(map, type_row);
        if (reference.x == EX_INVALID)
            reference = uint2(semantic_param_ref_tag_by_row[source], semantic_param_ref_payload_by_row[source]);
        semantic_param_ref_tag_by_row[index] = reference.x;
        semantic_param_ref_payload_by_row[index] = reference.y;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    for (uint k = 0u; k < EX_TABLES; k++) copy_slot(k, lane);
}
