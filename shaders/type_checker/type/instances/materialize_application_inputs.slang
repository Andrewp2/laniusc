import type_checker.concrete_type_equality;
// Create checked applications required by record fields and local enum payloads. Source
// type rows are immutable. Independent roots own their traversal stacks and
// atomically reserve private rows; completed rows are indexed in a later pass.
import hir_records;
import atomics;
import status;
import type_checker.mutable_checked_type_graph;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.local_struct_layout;
import dependency_interface;
import type_checker.dependencies.canonical_field_types;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> type_instance_lookup_head;
StructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_application_count;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;
RWStructuredBuffer<uint> type_native_word_count;
RWStructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DEPTH_LIMIT = 64u;
static const uint ARG_LIMIT = 32u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

uint type_token(uint node)
{
    if (node >= hir_count()) return INVALID;
    uint head = compact_hir_core[node].token_start;
    if (head < gParams.n_tokens && type_expr_ref_tag[head] != 0u) return head;
    uint path = path_id_by_owner_hir[node];
    if (path < min(path_count_out[0u], gParams.n_hir_nodes))
    {
        uint count = path_segment_count[path];
        uint row = count != 0u ? path_segment_base[path] + count - 1u : INVALID;
        if (row < gParams.n_tokens) return path_segment_token[row];
    }
    return INVALID;
}

