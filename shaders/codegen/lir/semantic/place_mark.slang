import hir_records;
import hir_expr_semantics;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import checked_semantic_artifact;
import native_value_layout;
import gpu_index;
struct Params { uint n_hir_nodes; uint n_tokens; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_word_count;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_native_words;
RWStructuredBuffer<uint4> semantic_place_storage_by_token;
RWStructuredBuffer<uint> semantic_place_function_flags;
RWStructuredBuffer<uint> semantic_receiver_call_by_hir;
RWStructuredBuffer<LoweringStatus> lowering_status;

void reject_place(uint node)
{
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, node);
}

uint4 storage_for_type(uint tag, uint type, uint words)
{
    if (tag == 1u && type > 0u && type < 128u)
        return uint4(type == 7u ? 2u : 1u, type == 7u ? 2u : 1u, 8u, 0u);
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (tag == 3u && type < capacity)
    {
        uint kind = type_instance_kind[type];
        if (kind == 4u) return uint4(1u, 1u, 8u, 0u);
        if (kind == 3u) return uint4(2u, NATIVE_SLICE_WORDS, 8u, 0u);
        uint instance_words = type_instance_native_words[type];
        if ((kind == 1u || kind == 2u) && instance_words != LIR_INVALID)
            return uint4(3u, instance_words, 8u, 0u);
    }
    return tag == 1u && type >= 128u && words != LIR_INVALID
        ? uint4(3u, words, 8u, 0u) : uint4(0u, 0u, 0u, 0u);
}

uint4 storage_for_hir(uint node, uint count)
{
    uint words = semantic_aggregate_word_count[node];
    uint token = semantic_aggregate_decl_token[node];
    if (token < gParams.n_tokens)
    {
        uint owner = semantic_aggregate_hir_by_name_token[token];
        if (owner < count) words = semantic_struct_word_count_by_hir[owner];
    }
    return storage_for_type(semantic_expr_ref_tag[node], semantic_expr_ref_payload[node], words);
}

#include "receiver_words.slang"
#include "receiver_temporary.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= count || compact_hir_core[row].kind != HIR_CALL_EXPR ||
        semantic_function_id[row] == LIR_INVALID) return;
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    if (call.receiver_hir == LIR_INVALID) return;
    uint source = call.receiver_hir;
    if (source >= count || call.receiver_adjustment_kind < 1u ||
        call.receiver_adjustment_kind > 2u || call.receiver_deref_count > 64u ||
        call.receiver_matched_ref_tag == 0u || call.receiver_parameter_ref_tag == 0u)
    { reject_place(row); return; }
    uint previous;
    InterlockedCompareExchange(semantic_receiver_call_by_hir[source], 0u, row + 1u, previous);
    if (previous != 0u && previous != row + 1u)
    { reject_place(row); return; }
    if (call.receiver_adjustment_kind != 2u || call.receiver_deref_count != 0u) return;

    // A receiver that is not a place gets the call's own local, sized by
    // the matched receiver type (receiver_temporary.slang).
    uint temporary = receiver_temporary_token(row, call, count);
    if (temporary != LIR_INVALID)
    {
        uint tag = call.receiver_matched_ref_tag;
        uint type = call.receiver_matched_ref_payload;
        uint4 storage = storage_for_type(tag, type, receiver_native_words(tag, type, count));
        if (temporary >= gParams.n_tokens || storage.x == 0u || storage.y > 0xffffu)
        { reject_place(source); return; }
        semantic_place_storage_by_token[temporary] = storage;
        uint owner = semantic_function_id[row];
        InterlockedOr(semantic_place_function_flags[semantic_lir_functions[owner].hir_function], 1u);
        return;
    }

    // Place projections consume the existing base/index evaluations. Mark
    // the root storage before any initialization or value use is lowered.
    uint root = source;
    bool index_container_edge = false;
    for (uint depth = 0u; depth < 64u && root < count; depth++)
    {
        HirCore core = compact_hir_core[root];
        HirPayload payload = compact_hir_payload[root];
        if (core.kind == HIR_MEMBER_EXPR || core.kind == HIR_INDEX_EXPR)
        {
            // Remember the projection that consumes this base. A slice value
            // provides backing storage for an index, not its own descriptor cell.
            index_container_edge = core.kind == HIR_INDEX_EXPR;
            root = payload.b;
            continue;
        }
        if (hir_is_forward_expression(core.kind, payload.a))
        { root = payload.b; continue; }
        if ((core.kind == HIR_NAME_EXPR || core.kind == HIR_PATH_EXPR || core.kind == HIR_EXPR) &&
            payload.a == HIR_EXPR_NAME)
        {
            uint declaration = semantic_value_id[root];
            uint4 storage = storage_for_hir(root, count);
            if (declaration >= gParams.n_tokens || storage.x == 0u || storage.y > 0xffffu)
            { reject_place(source); return; }
            InterlockedMax(semantic_place_storage_by_token[declaration].x, storage.x);
            InterlockedMax(semantic_place_storage_by_token[declaration].y, storage.y);
            InterlockedMax(semantic_place_storage_by_token[declaration].z, storage.z);
            uint function = semantic_function_id[row];
            InterlockedOr(semantic_place_function_flags[semantic_lir_functions[function].hir_function], 1u);
            return;
        }
        // A reference-valued base names caller storage. A slice descriptor
        // also names backing storage when the next projection indexes it.
        // Neither case borrows the temporary value's own descriptor/pointer cell.
        if (root != source && semantic_expr_ref_tag[root] == 3u)
        {
            uint capacity; uint stride;
            type_instance_kind.GetDimensions(capacity, stride);
            uint instance = semantic_expr_ref_payload[root];
            if (instance < capacity)
            {
                uint kind = type_instance_kind[instance];
                if (kind == 4u || (kind == 3u && index_container_edge)) return;
            }
        }
        break;
    }
    reject_place(source);
}
