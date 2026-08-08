use super::*;
use crate::gpu::compiler_graph::{CompilerGraphBuilder, ReflectedComputeSpec};

pub(in crate::type_checker) const CONDITIONS_CALLS: ReflectedComputeSpec = typecheck_operation!(
    "type_check.conditions.compact_calls", HirNodes, "type_checker/conditions/compact_calls";
    resources [
        typecheck_resource!("call_fn_index" => "backend_call_fn_index"),
        typecheck_resource!("call_dependency_library_id" => "call_dependency_library_id", Read),
        typecheck_resource!("module_value_path_associated_method_token" => "module_value_path_associated_method_token", Read),
    ]
);
pub(in crate::type_checker) const CONDITIONS_TYPES: ReflectedComputeSpec = typecheck_pass!(
    "type_check.conditions.compact_types",
    HirNodes,
    "type_checker/conditions/compact_types"
);
pub(in crate::type_checker) const CONDITIONS_METHODS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.conditions.compact_methods",
    Declarations,
    "type_checker/conditions/compact_methods"
);
pub(in crate::type_checker) const CONDITIONS_PREDICATES: ReflectedComputeSpec = typecheck_pass!(
    "type_check.conditions.compact_predicates",
    Declarations,
    "type_checker/conditions/compact_predicates"
);
pub(in crate::type_checker) const CONDITIONS_NAMES: ReflectedComputeSpec = typecheck_operation!(
    "type_check.conditions.compact_names", HirNodes, "type_checker/conditions/compact_names";
    resources [typecheck_resource!("call_fn_index" => "backend_call_fn_index")]
);

/// Final condition projection after aggregate comparison has completed.
pub(in crate::type_checker) struct ConditionFinalizationOperation {
    calls: ComputeOperation,
    types: ComputeOperation,
    methods: ComputeOperation,
    predicates: ComputeOperation,
    names: ComputeOperation,
}

impl ConditionFinalizationOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        kernels: &KernelRegistry,
        hir_capacity: u32,
        method_dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let direct = |spec| {
            ComputeOperation::direct_spec(device, graph, resources, kernels, spec, hir_capacity)
        };
        Ok(Self {
            calls: direct(CONDITIONS_CALLS)?,
            types: direct(CONDITIONS_TYPES)?,
            methods: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                CONDITIONS_METHODS,
                method_dispatch_args,
            )?,
            predicates: direct(CONDITIONS_PREDICATES)?,
            names: direct(CONDITIONS_NAMES)?,
        })
    }

    pub(in crate::type_checker) fn register(
        graph: &mut CompilerGraphBuilder,
        kernels: &impl crate::gpu::kernels::KernelReflections,
    ) -> Result<(), String> {
        for spec in [
            CONDITIONS_CALLS,
            CONDITIONS_TYPES,
            CONDITIONS_METHODS,
            CONDITIONS_PREDICATES,
            CONDITIONS_NAMES,
        ] {
            spec.register_kernel(graph, kernels)?;
        }
        Ok(())
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.calls.record(encoder)?;
        self.types.record(encoder)?;
        self.methods.record(encoder)?;
        self.predicates.record(encoder)?;
        self.names.record(encoder)
    }
}
