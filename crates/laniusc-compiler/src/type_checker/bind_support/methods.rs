use super::super::*;

/// Builds method declaration and method-call resolution bind groups.
pub(in crate::type_checker) fn create_method_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    keys: MethodIndex,
    token_args: &LaniusBuffer<u32>,
    method_token_args: &LaniusBuffer<u32>,
    method_compact_args: &LaniusBuffer<u32>,
    method_hir_args: &LaniusBuffer<u32>,
    method_token_hir_args: &LaniusBuffer<u32>,
) -> Result<MethodBindGroups> {
    let indirect =
        |spec, args| ComputeOperation::indirect_spec(device, graph, resources, passes, spec, args);
    Ok(MethodBindGroups {
        clear: indirect(METHODS_CLEAR, token_args)?,
        collect: indirect(METHODS_COLLECT, method_compact_args)?,
        attach_metadata: indirect(METHODS_ATTACH_METADATA, method_compact_args)?,
        bind_self_receivers: indirect(METHODS_BIND_SELF_RECEIVERS, method_hir_args)?,
        keys,
        mark_call_keys: indirect(METHODS_MARK_CALL_KEYS, method_token_hir_args)?,
        mark_call_return_keys: indirect(METHODS_MARK_CALL_RETURN_KEYS, method_hir_args)?,
        resolve_table: indirect(METHODS_RESOLVE_TABLE, method_token_args)?,
        resolve: indirect(METHODS_RESOLVE, method_token_hir_args)?,
    })
}
