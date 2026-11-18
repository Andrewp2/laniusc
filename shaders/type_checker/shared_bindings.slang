// Shader parameters that kernels fused into one dispatch both bind. A kernel
// body that runs inside a fused kernel imports the bindings it shares from
// here instead of declaring them, so the fused kernel declares each once.
// Add a binding here when a new fusion shares it.

import shared.syntax.hir_records;

// A prefix of the type checker's parameter block (TypeCheckParams in
// type_checker/params.rs).
public struct TypeCheckParams
{
    public uint n_tokens;
    public uint source_len;
    public uint n_hir_nodes;
    public uint n_source_files;
    public uint parser_feature_flags;
};

public ConstantBuffer<TypeCheckParams> gParams;

public StructuredBuffer<HirCore> compact_hir_core;
public StructuredBuffer<HirPayload> compact_hir_payload;
public StructuredBuffer<uint> decl_name_token;
public StructuredBuffer<uint> path_count_out;
public StructuredBuffer<uint> path_id_by_owner_hir;
public StructuredBuffer<uint> resolved_type_decl;
public StructuredBuffer<uint> struct_lit_context_decl_token;
public StructuredBuffer<uint> struct_lit_context_instance;
public StructuredBuffer<uint> type_decl_hir_node_by_token;
public StructuredBuffer<uint> type_expr_ref_payload;
public StructuredBuffer<uint> type_expr_ref_tag;
public StructuredBuffer<uint> type_instance_decl_token;
public StructuredBuffer<uint> visible_decl;
