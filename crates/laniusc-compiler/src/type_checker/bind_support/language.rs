use super::super::*;

/// Builds bind groups for builtin language names and builtin declarations.
pub(in crate::type_checker) fn create_language_name_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    resources: &ResourceMap<'_>,
    name_capacity: u32,
) -> Result<LanguageNameBindGroups> {
    Ok(LanguageNameBindGroups {
        clear: ComputeOperation::direct(
            device,
            graph,
            resources,
            compiler_graph::LANGUAGE_NAMES_CLEAR_PASS,
            &passes.kernel("type_checker/language/names/00_clear"),
            LANGUAGE_SYMBOL_COUNT,
        )?,
        type_codes_clear: ComputeOperation::direct(
            device,
            graph,
            resources,
            compiler_graph::LANGUAGE_TYPE_CODES_CLEAR_PASS,
            &passes.kernel("type_checker/language/decls/00a_clear_type_codes"),
            name_capacity,
        )?,
        decls_materialize: ComputeOperation::direct(
            device,
            graph,
            resources,
            compiler_graph::LANGUAGE_DECLS_MATERIALIZE_PASS,
            &passes.kernel("type_checker/language/decls/00_materialize"),
            LANGUAGE_DECL_COUNT,
        )?,
    })
}
