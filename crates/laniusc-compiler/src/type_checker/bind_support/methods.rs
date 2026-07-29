use super::super::*;

/// Builds method declaration and method-call resolution bind groups.
pub(in crate::type_checker) fn create_method_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    keys: MethodKeyPipeline,
    token_args: &wgpu::Buffer,
    method_token_args: &wgpu::Buffer,
    method_compact_args: &wgpu::Buffer,
    method_hir_args: &wgpu::Buffer,
    method_token_hir_args: &wgpu::Buffer,
) -> Result<MethodBindGroups> {
    let indirect = |spec, pass, args| {
        ComputeOperation::indirect_spec(device, graph, resources, spec, pass, args)
    };
    Ok(MethodBindGroups {
        clear: indirect(METHODS_CLEAR, &passes.methods_clear, token_args)?,
        collect: indirect(
            METHODS_COLLECT,
            &passes.methods_collect,
            method_compact_args,
        )?,
        attach_metadata: indirect(
            METHODS_ATTACH_METADATA,
            &passes.methods_attach_metadata,
            method_token_args,
        )?,
        bind_self_receivers: indirect(
            METHODS_BIND_SELF_RECEIVERS,
            &passes.methods_bind_self_receivers,
            method_hir_args,
        )?,
        keys,
        mark_call_keys: indirect(
            METHODS_MARK_CALL_KEYS,
            &passes.methods_mark_call_keys,
            method_token_hir_args,
        )?,
        mark_call_return_keys: indirect(
            METHODS_MARK_CALL_RETURN_KEYS,
            &passes.methods_mark_call_return_keys,
            method_hir_args,
        )?,
        resolve_table: indirect(
            METHODS_RESOLVE_TABLE,
            &passes.methods_resolve_table,
            method_token_args,
        )?,
        resolve: indirect(
            METHODS_RESOLVE,
            &passes.methods_resolve,
            method_token_hir_args,
        )?,
    })
}
