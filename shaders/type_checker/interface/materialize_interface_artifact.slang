import semantic_interface_layout;
// Materialize the exact persisted semantic-interface byte stream on the GPU.
// Every lane copies one row from each compact table when that row is active;
// the host reads only the byte length written by lane zero.

import gpu_index;
import atomics;

struct Params
{
    uint module_capacity;
    uint module_segment_capacity;
    uint declaration_capacity;
    uint type_capacity;
    uint edge_capacity;
    uint member_capacity;
    uint name_byte_capacity;
    uint artifact_word_capacity;
    uint unit_id;
    uint version;
    uint predicate_capacity;
    uint predicate_argument_capacity;
    uint implementation_capacity;
    uint implementation_argument_capacity;
    uint implementation_method_binding_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_counts;
StructuredBuffer<uint> interface_complete_type_count;
StructuredBuffer<uint> interface_complete_edge_total;
StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_modules;
StructuredBuffer<uint> interface_module_segments;
StructuredBuffer<uint> interface_declaration_words;
StructuredBuffer<uint> interface_types;
StructuredBuffer<uint> interface_edges;
StructuredBuffer<uint> interface_edge_written;
StructuredBuffer<uint> interface_member_words;
StructuredBuffer<uint> interface_member_written;
StructuredBuffer<uint> interface_predicate_total;
StructuredBuffer<uint> interface_predicate_argument_total;
StructuredBuffer<uint> interface_predicate_words;
StructuredBuffer<uint> interface_predicate_written;
StructuredBuffer<uint> interface_predicate_arguments;
StructuredBuffer<uint> interface_predicate_argument_written;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_implementation_argument_total;
StructuredBuffer<uint> interface_implementation_method_total;
StructuredBuffer<uint> interface_implementation_words;
StructuredBuffer<uint> interface_implementation_written;
StructuredBuffer<uint> interface_implementation_arguments;
StructuredBuffer<uint> interface_implementation_argument_written;
StructuredBuffer<uint> interface_implementation_method_binding_words;
StructuredBuffer<uint> interface_implementation_method_binding_written;
StructuredBuffer<uint> interface_name_byte_words;
RWStructuredBuffer<uint> interface_status;
RWStructuredBuffer<uint> interface_artifact_words;
RWStructuredBuffer<uint> interface_artifact_length;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HEADER_WORDS = 18u;
static const uint MODULE_WORDS = 2u;
static const uint MODULE_SEGMENT_WORDS = 4u;
static const uint DECLARATION_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint MEMBER_WORDS =SEMANTIC_INTERFACE_MEMBER_WORDS;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

void copy_words(
    uint row,
    uint row_count,
    uint words_per_row,
    uint destination_start,
    StructuredBuffer<uint> source)
{
    if (row >= row_count)
        return;
    uint source_start = row * words_per_row;
    uint destination = destination_start + source_start;
    for (uint word = 0u; word < words_per_row; ++word)
        interface_artifact_words[destination + word] = source[source_start + word];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint module_count = interface_counts[1u];
    uint module_segment_count = interface_counts[2u];
    uint declaration_count = interface_counts[3u];
    uint name_byte_count = interface_counts[4u];
    uint type_count = interface_complete_type_count[0u];
    uint edge_count = interface_complete_edge_total[0u];
    uint member_count = interface_member_total[0u];
    uint predicate_count = interface_predicate_total[0u];
    uint predicate_argument_count = interface_predicate_argument_total[0u];
    uint implementation_count = interface_implementation_total[0u];
    uint implementation_argument_count = interface_implementation_argument_total[0u];
    uint implementation_method_binding_count = interface_implementation_method_total[0u];

    bool valid = module_count <= gParams.module_capacity
              && module_segment_count <= gParams.module_segment_capacity
              && declaration_count <= gParams.declaration_capacity
              && type_count <= gParams.type_capacity
              && edge_count <= gParams.edge_capacity
              && member_count <= gParams.member_capacity
              && predicate_count <= gParams.predicate_capacity
              && predicate_argument_count <= gParams.predicate_argument_capacity
              && implementation_count <= gParams.implementation_capacity
              && implementation_argument_count <= gParams.implementation_argument_capacity
              && implementation_method_binding_count <= gParams.implementation_method_binding_capacity
              && name_byte_count <= gParams.name_byte_capacity;
    uint module_start = HEADER_WORDS;
    uint module_segment_start = module_start + module_count * MODULE_WORDS;
    uint declaration_start = module_segment_start + module_segment_count * MODULE_SEGMENT_WORDS;
    uint type_start = declaration_start + declaration_count * DECLARATION_WORDS;
    uint edge_start = type_start + type_count * TYPE_WORDS;
    uint member_start = edge_start + edge_count;
    uint predicate_start = member_start + member_count * MEMBER_WORDS;
    uint predicate_argument_start = predicate_start + predicate_count * SEMANTIC_INTERFACE_PREDICATE_WORDS;
    uint implementation_start = predicate_argument_start + predicate_argument_count;
    uint implementation_argument_start = implementation_start + implementation_count * SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS;
    uint implementation_method_binding_start = implementation_argument_start + implementation_argument_count;
    uint name_start = implementation_method_binding_start + implementation_method_binding_count * SEMANTIC_INTERFACE_IMPLEMENTATION_METHOD_BINDING_WORDS;
    uint artifact_words = name_start + (name_byte_count + 3u) / 4u;
    valid = valid && artifact_words <= gParams.artifact_word_capacity;
    if (!valid)
    {
        if (row == 0u)
        {
            atomic_u32_or(interface_status, 0u, 0x80000000u);
            interface_status[1u] = (module_count > gParams.module_capacity ? 1u : 0u) |
                (module_segment_count > gParams.module_segment_capacity ? 2u : 0u) |
                (declaration_count > gParams.declaration_capacity ? 4u : 0u) |
                (type_count > gParams.type_capacity ? 8u : 0u) |
                (edge_count > gParams.edge_capacity ? 16u : 0u) |
                (member_count > gParams.member_capacity ? 32u : 0u) |
                (name_byte_count > gParams.name_byte_capacity ? 64u : 0u) |
                (artifact_words > gParams.artifact_word_capacity ? 128u : 0u) |
                (predicate_count > gParams.predicate_capacity ? 256u : 0u) |
                (predicate_argument_count > gParams.predicate_argument_capacity ? 512u : 0u) |
                (implementation_count > gParams.implementation_capacity ? 1024u : 0u) |
                (implementation_argument_count > gParams.implementation_argument_capacity ? 2048u : 0u) |
                (implementation_method_binding_count > gParams.implementation_method_binding_capacity ? 4096u : 0u);
            interface_artifact_length[0u] = 0u;
        }
        return;
    }
    if (row < edge_count && interface_edge_written[row] != 1u)
    {
        atomic_u32_or(interface_status, 0u, 0x20000000u);
        atomic_u32_min(interface_status, 1u, row);
    }
    if (row < member_count && interface_member_written[row] != 1u)
        atomic_u32_or(interface_status, 0u, 0x40000000u);

    if ((row < predicate_count && interface_predicate_written[row] != 1u) ||
        (row < predicate_argument_count && interface_predicate_argument_written[row] != 1u))
    {
        atomic_u32_or(interface_status, 0u, 65536u);
        atomic_u32_min(interface_status, 1u, row);
    }

    if ((row < implementation_count && interface_implementation_written[row] != 1u) ||
        (row < implementation_argument_count && interface_implementation_argument_written[row] != 1u) ||
        (row < implementation_method_binding_count && interface_implementation_method_binding_written[row] != 1u))
    {
        atomic_u32_or(interface_status, 0u, 131072u);
        atomic_u32_min(interface_status, 1u, row);
    }

    if (row == 0u)
    {
        interface_artifact_words[0u] = 0x49534e4cu; // "LNSI"
        interface_artifact_words[1u] = 0x45434146u; // "FACE"
        interface_artifact_words[2u] = gParams.version;
        interface_artifact_words[3u] = interface_counts[0u];
        interface_artifact_words[4u] = module_count;
        interface_artifact_words[5u] = module_segment_count;
        interface_artifact_words[6u] = declaration_count;
        interface_artifact_words[7u] = type_count;
        interface_artifact_words[8u] = edge_count;
        interface_artifact_words[9u] = member_count;
        interface_artifact_words[10u] = name_byte_count;
        interface_artifact_words[11u] = gParams.unit_id;
        interface_artifact_words[12u] = predicate_count;
        interface_artifact_words[13u] = predicate_argument_count;
        interface_artifact_words[14u] = implementation_count;
        interface_artifact_words[15u] = implementation_argument_count;
        interface_artifact_words[16u] = implementation_method_binding_count;
        interface_artifact_words[17u] = 0u;
        interface_artifact_length[0u] = name_start * 4u + name_byte_count;
    }

    copy_words(row, module_count, MODULE_WORDS, module_start, interface_modules);
    copy_words(
        row,
        module_segment_count,
        MODULE_SEGMENT_WORDS,
        module_segment_start,
        interface_module_segments);
    copy_words(
        row,
        declaration_count,
        DECLARATION_WORDS,
        declaration_start,
        interface_declaration_words);
    copy_words(row, type_count, TYPE_WORDS, type_start, interface_types);
    copy_words(row, edge_count, 1u, edge_start, interface_edges);
    copy_words(row, member_count, MEMBER_WORDS, member_start, interface_member_words);
    copy_words(row, predicate_count, SEMANTIC_INTERFACE_PREDICATE_WORDS, predicate_start, interface_predicate_words);
    copy_words(row, predicate_argument_count, 1u, predicate_argument_start, interface_predicate_arguments);
    copy_words(row, implementation_count, SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS, implementation_start, interface_implementation_words);
    copy_words(row, implementation_argument_count, 1u, implementation_argument_start, interface_implementation_arguments);
    copy_words(row, implementation_method_binding_count, SEMANTIC_INTERFACE_IMPLEMENTATION_METHOD_BINDING_WORDS,
        implementation_method_binding_start, interface_implementation_method_binding_words);
    copy_words(
        row,
        (name_byte_count + 3u) / 4u,
        1u,
        name_start,
        interface_name_byte_words);
}
