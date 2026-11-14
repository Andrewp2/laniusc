// Execution-row layout (instance_exec.slang): one lane, after the
// selection. In table order, every eligible entry receives its virtual
// rows after the job's compact HIR, its virtual tokens after the job's
// token capacity, and its blocks after each side table's rows. Lowering
// sizes its token tables for a 1/EX_VIRTUAL_TOKEN_DIVISOR share of the
// capacity (exec_lowering_token_capacity in instance_closure_passes.rs).
// Checked type rows are numbered from the end of the type checker's token
// tables (type/instances/allocate_application.slang), and lowering reads
// type rows and tokens in one id space, so virtual tokens also end before
// those tables do. An entry past any capacity, and every later entry,
// replays (EX_FLAG_CAPACITY). Also sizes the row and table dispatches.
import hir_records;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<HirString> compact_strings;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
// Per-row semantic outputs bound the virtual rows like the HIR does.
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_param_ref_tag_by_row;
StructuredBuffer<uint> struct_init_field_ordinal_by_row;
StructuredBuffer<uint> compact_match_payload_start;
// Its length is the first checked type row (allocate_application.slang).
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> instance_exec_args;
RWStructuredBuffer<uint> instance_exec_table_args;

// Virtual tokens per job token: lowering's token tables hold the job's
// capacity plus this share (EX_VIRTUAL_TOKEN_DIVISOR in Rust).
static const uint EX_VIRTUAL_TOKEN_DIVISOR = 4u;

uint dims_hir_core() { uint rows; uint stride; compact_hir_core.GetDimensions(rows, stride); return rows; }
uint dims_expr() { uint rows; uint stride; semantic_expr_ref_tag_by_hir.GetDimensions(rows, stride); return rows; }

uint table_count(uint k)
{
    if (k == EX_TABLE_CALL_ARGS) return compact_call_arg_count[0u];
    if (k == EX_TABLE_FIELDS) return compact_field_count[0u];
    if (k == EX_TABLE_MATCH_ARMS) return compact_match_arm_count[0u];
    if (k == EX_TABLE_MATCH_PAYLOADS) return compact_match_payload_row_count[0u];
    if (k == EX_TABLE_ARRAY_ELEMENTS) return compact_array_element_row_count[0u];
    if (k == EX_TABLE_STRINGS) return compact_string_count[0u];
    return compact_param_count[0u];
}

uint table_capacity(uint k)
{
    uint rows; uint stride;
    uint second = 0xffffffffu;
    if (k == EX_TABLE_CALL_ARGS) compact_call_args.GetDimensions(rows, stride);
    else if (k == EX_TABLE_FIELDS)
    {
        compact_fields.GetDimensions(rows, stride);
        struct_init_field_ordinal_by_row.GetDimensions(second, stride);
    }
    else if (k == EX_TABLE_MATCH_ARMS)
    {
        compact_match_arms.GetDimensions(rows, stride);
        compact_match_payload_start.GetDimensions(second, stride);
    }
    else if (k == EX_TABLE_MATCH_PAYLOADS) compact_match_payloads.GetDimensions(rows, stride);
    else if (k == EX_TABLE_ARRAY_ELEMENTS) compact_array_elements.GetDimensions(rows, stride);
    else if (k == EX_TABLE_STRINGS) compact_strings.GetDimensions(rows, stride);
    else
    {
        compact_params.GetDimensions(rows, stride);
        semantic_param_ref_tag_by_row.GetDimensions(second, stride);
    }
    return min(rows, second);
}

uint3 dispatch_size(uint lanes)
{
    uint groups = (lanes + 255u) / 256u;
    uint x = min(groups, 65535u);
    return uint3(x, x == 0u ? 0u : (groups + 65534u) / 65535u, 1u);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint hir = min(compact_hir_count[0u], dims_hir_core());
    // Lowering visits the rows below the job's token capacity plus two
    // (LoweringJobBounds::with_token_capacity).
    uint row_capacity = min(min(min(dims_hir_core(), dims_expr()), gParams.n_hir_nodes),
        gParams.n_tokens + 2u);
    uint token_base = gParams.n_tokens;
    uint source_capacity; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
    uint token_capacity = min(gParams.n_tokens / EX_VIRTUAL_TOKEN_DIVISOR,
        source_capacity > token_base ? source_capacity - token_base : 0u);
    uint4 own0 = uint4(0u, 0u, 0u, 0u);
    uint4 own1 = uint4(0u, 0u, 0u, 0u);
    uint4 room0 = uint4(0u, 0u, 0u, 0u);
    uint4 room1 = uint4(0u, 0u, 0u, 0u);
    uint4 used0 = uint4(0u, 0u, 0u, 0u);
    uint4 used1 = uint4(0u, 0u, 0u, 0u);
    for (uint k = 0u; k < EX_TABLES; k++)
    {
        uint own = table_count(k);
        uint capacity = table_capacity(k);
        ex_set_table_word(own0, own1, k, own);
        ex_set_table_word(room0, room1, k, own <= capacity ? capacity - own : 0u);
        instance_exec_counts[EX_COUNT_TABLE_BASE + k] = own;
    }
    instance_exec_counts[EX_COUNT_HIR] = hir;
    instance_exec_counts[EX_COUNT_TOKEN_BASE] = token_base;
    uint row_room = hir <= row_capacity ? row_capacity - hir : 0u;
    uint entries = min(min(instance_table_counts[IT_COUNT_ENTRIES], IT_RANK_LIMIT), ex_entry_capacity());
    uint selected = 0u;
    uint rows = 0u;
    uint tokens = 0u;
    bool full = false;
    for (uint entry = 0u; entry < entries; entry++)
    {
        uint4 head = ex_quad(entry, EX_Q_HEAD);
        if (head.x != EX_PENDING) continue;
        uint4 span = ex_quad(entry, EX_Q_TOKENS);
        uint4 length0 = ex_quad(entry, EX_Q_TLEN0);
        uint4 length1 = ex_quad(entry, EX_Q_TLEN1);
        bool fits = !full && head.z <= row_room - rows && span.y <= token_capacity - tokens;
        for (uint k = 0u; k < EX_TABLES && fits; k++)
            fits = ex_table_word(length0, length1, k) <=
                ex_table_word(room0, room1, k) - ex_table_word(used0, used1, k);
        if (!fits)
        {
            full = true;
            ex_set_quad(entry, EX_Q_HEAD, uint4(EX_REJECT_CAPACITY, head.y, head.z, 0xffffffffu));
            continue;
        }
        uint4 start0 = own0 + used0;
        uint4 start1 = own1 + used1;
        used0 += length0;
        used1 += length1;
        ex_set_quad(entry, EX_Q_HEAD, uint4(EX_SELECTED, head.y, head.z, hir + rows));
        ex_set_quad(entry, EX_Q_TOKENS, uint4(span.x, span.y, token_base + tokens, span.w));
        ex_set_quad(entry, EX_Q_VSTART0, start0);
        ex_set_quad(entry, EX_Q_VSTART1, start1);
        instance_exec_list[selected] = entry;
        selected++;
        rows += head.z;
        tokens += span.y;
    }
    uint most = 0u;
    for (uint k = 0u; k < EX_TABLES; k++)
    {
        uint used = ex_table_word(used0, used1, k);
        instance_exec_counts[EX_COUNT_TABLE + k] = used;
        most = max(most, used);
    }
    instance_exec_counts[EX_COUNT_ENTRIES] = selected;
    instance_exec_counts[EX_COUNT_ROWS] = rows;
    instance_exec_counts[EX_COUNT_TOKENS] = tokens;
    instance_exec_counts[EX_COUNT_FLAGS] = full ? EX_FLAG_CAPACITY : 0u;
    uint3 row_groups = dispatch_size(rows);
    uint3 table_groups = dispatch_size(most);
    instance_exec_args[0u] = row_groups.x;
    instance_exec_args[1u] = row_groups.y;
    instance_exec_args[2u] = row_groups.z;
    instance_exec_table_args[0u] = table_groups.x;
    instance_exec_table_args[1u] = table_groups.y;
    instance_exec_table_args[2u] = table_groups.z;
}
