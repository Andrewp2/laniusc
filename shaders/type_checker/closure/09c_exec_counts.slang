// Lowering's row counts (instance_exec.slang): one lane at the end of every
// type check. Lowering reads the job's compact HIR and side tables through
// these counts, which include the execution rows a selected instance
// appended (none when the job built no table: its counters are clear).
import hir_records;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<uint> compact_param_count;
RWStructuredBuffer<uint> exec_hir_count;
RWStructuredBuffer<uint> exec_call_arg_count;
RWStructuredBuffer<uint> exec_field_count;
RWStructuredBuffer<uint> exec_match_arm_count;
RWStructuredBuffer<uint> exec_match_payload_row_count;
RWStructuredBuffer<uint> exec_array_element_row_count;
RWStructuredBuffer<uint> exec_string_count;
RWStructuredBuffer<uint> exec_param_count;

// The job's own rows, plus the virtual rows only when the layout placed them
// right after these rows (it read the same counts).
uint total(uint own, uint k)
{
    bool placed = instance_exec_counts[EX_COUNT_ENTRIES] != 0u &&
        instance_exec_counts[EX_COUNT_TABLE_BASE + k] == own;
    return placed ? own + instance_exec_counts[EX_COUNT_TABLE + k] : own;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint hir = compact_hir_count[0u];
    bool placed = instance_exec_counts[EX_COUNT_ENTRIES] != 0u && instance_exec_counts[EX_COUNT_HIR] == hir;
    exec_hir_count[0u] = placed ? hir + instance_exec_counts[EX_COUNT_ROWS] : hir;
    exec_call_arg_count[0u] = total(compact_call_arg_count[0u], EX_TABLE_CALL_ARGS);
    exec_field_count[0u] = total(compact_field_count[0u], EX_TABLE_FIELDS);
    exec_match_arm_count[0u] = total(compact_match_arm_count[0u], EX_TABLE_MATCH_ARMS);
    exec_match_payload_row_count[0u] = total(compact_match_payload_row_count[0u], EX_TABLE_MATCH_PAYLOADS);
    exec_array_element_row_count[0u] = total(compact_array_element_row_count[0u], EX_TABLE_ARRAY_ELEMENTS);
    exec_string_count[0u] = total(compact_string_count[0u], EX_TABLE_STRINGS);
    exec_param_count[0u] = total(compact_param_count[0u], EX_TABLE_PARAMS);
}
