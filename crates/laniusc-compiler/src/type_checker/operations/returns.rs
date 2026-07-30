use super::*;
use crate::gpu::compiler_graph::{CompilerGraphBuilder, ReflectedComputeSpec};

pub(in crate::type_checker) const RETURNS_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.returns.clear", HirNodes, "type_checker/returns/00_clear";
    writes ["return_fn_flags", "return_block_flags"]
);
pub(in crate::type_checker) const RETURNS_MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.returns.mark",
    HirNodes,
    "type_checker/returns/01_mark"
);
pub(in crate::type_checker) const RETURNS_MARK_IF: ReflectedComputeSpec = typecheck_pass!(
    "type_check.returns.mark_if",
    HirNodes,
    "type_checker/returns/02_mark_if"
);
pub(in crate::type_checker) const RETURNS_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.returns.validate",
    HirNodes,
    "type_checker/returns/03_validate"
);

/// Computes and validates function/block return coverage.
pub(in crate::type_checker) struct ReturnValidationOperation {
    clear: ComputeOperation,
    mark: ComputeOperation,
    mark_if: ComputeOperation,
    validate: ComputeOperation,
}

impl ReturnValidationOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        kernels: &KernelRegistry,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<Self> {
        let operation = |spec| {
            ComputeOperation::indirect_spec(device, graph, resources, kernels, spec, dispatch_args)
        };
        Ok(Self {
            clear: operation(RETURNS_CLEAR)?,
            mark: operation(RETURNS_MARK)?,
            mark_if: operation(RETURNS_MARK_IF)?,
            validate: operation(RETURNS_VALIDATE)?,
        })
    }

    pub(in crate::type_checker) fn register(
        graph: &mut CompilerGraphBuilder,
        kernels: &impl crate::gpu::kernels::KernelReflections,
    ) -> Result<(), String> {
        for spec in [
            RETURNS_CLEAR,
            RETURNS_MARK,
            RETURNS_MARK_IF,
            RETURNS_VALIDATE,
        ] {
            spec.register_kernel(graph, kernels)?;
        }
        graph.repeat_pass_range(2, RETURNS_MARK_IF.name, RETURNS_MARK_IF.name)
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)?;
        self.mark.record(encoder)?;
        self.mark_if.record(encoder)?;
        self.mark_if.record(encoder)?;
        self.validate.record(encoder)
    }
}
