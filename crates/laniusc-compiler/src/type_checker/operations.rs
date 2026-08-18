//! Reusable GPU-parallel operations used to assemble semantic passes.

macro_rules! typecheck_pass {
    ($name:expr, $domain:ident, $kernel:expr) => {
        crate::gpu::compiler_graph::ReflectedComputeSpec::new(
            $name,
            $kernel,
            crate::gpu::compiler_graph::CompilerPhase::TypeCheck,
            crate::gpu::compiler_graph::ResourceDomain::$domain,
        )
    };
}

macro_rules! typecheck_resource {
    ($binding:expr => $resource:expr) => {
        crate::gpu::compiler_graph::ReflectedResourceAlias {
            binding: $binding,
            resource: $resource,
            mode: None,
        }
    };
    ($binding:expr => $resource:expr, $mode:ident) => {
        crate::gpu::compiler_graph::ReflectedResourceAlias {
            binding: $binding,
            resource: $resource,
            mode: Some(crate::gpu::compiler_graph::AccessMode::$mode),
        }
    };
}

macro_rules! typecheck_operation {
    (
        $name:expr, $domain:ident, $kernel:expr
        $(; writes [$($write:expr),* $(,)?])?
        $(; resources [$($resource:expr),* $(,)?])?
    ) => {
        typecheck_pass!($name, $domain, $kernel)
            $(.with_modes(&[$(($write, crate::gpu::compiler_graph::AccessMode::Write)),*]))?
            $(.with_aliases(&[$($resource),*]))?
    };
}

mod call_argument_matching;
mod call_claim_index;
mod call_generic_claim_validation;
mod calls;
mod conditions;
mod dependencies;
mod generic_parameter_index;
mod late_semantics;
mod methods;
mod module_paths;
mod names;
mod returns;
mod struct_field_index;
mod type_instances;
mod visible;
mod visible_decls;

pub(super) use call_argument_matching::*;
pub(super) use call_claim_index::*;
pub(super) use call_generic_claim_validation::*;
pub(super) use calls::*;
pub(super) use conditions::*;
pub(super) use dependencies::*;
pub(super) use generic_parameter_index::*;
pub(super) use late_semantics::*;
pub(super) use methods::*;
pub(super) use module_paths::*;
pub(super) use names::*;
pub(super) use returns::*;
pub(super) use struct_field_index::*;
pub(super) use type_instances::*;
pub(super) use visible::*;
pub(super) use visible_decls::*;

use super::*;
pub(super) use crate::gpu::operations::ComputeOperation;

/// A stable GPU compaction: produce flags, scan them, then scatter dense rows.
pub(super) struct CompactionOperation {
    mark: ComputeOperation,
    scan: PrefixScanOperation,
    scatter: ComputeOperation,
}

#[derive(Clone, Copy)]
pub(super) enum CompactionStage {
    Mark,
    Scan,
    Scatter,
}

impl CompactionOperation {
    pub(super) fn new(
        mark: ComputeOperation,
        scan: PrefixScanOperation,
        scatter: ComputeOperation,
    ) -> Self {
        Self {
            mark,
            scan,
            scatter,
        }
    }

    pub(super) fn indirect(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        kernels: &KernelRegistry,
        spec: crate::gpu::compiler_graph::CompactionSpec,
        dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self::new(
            ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                spec.mark,
                dispatch_args,
            )?,
            PrefixScanOperation::from_spec(device, kernels, resources, spec.scan)?,
            ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                spec.scatter,
                dispatch_args,
            )?,
        ))
    }

    pub(super) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_staged(encoder, |_, _| {})
    }

    pub(super) fn record_staged(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut after: impl FnMut(CompactionStage, &mut wgpu::CommandEncoder),
    ) -> Result<()> {
        self.mark.record(encoder)?;
        after(CompactionStage::Mark, encoder);
        self.scan.record(encoder)?;
        after(CompactionStage::Scan, encoder);
        self.scatter.record(encoder)?;
        after(CompactionStage::Scatter, encoder);
        Ok(())
    }
}

/// Discovers which optional semantic pass groups are needed by a job and
/// writes their indirect dispatch arguments. Reflection supplies the graph
/// access surface and bind-group surface; this value owns the executable
/// schedule so the resident recorder cannot reproduce it independently.
pub(super) struct SemanticFeaturesOperation {
    clear: crate::gpu::operations::ClearBufferOperation,
    collect: ComputeOperation,
    dispatch: ComputeOperation,
}

impl SemanticFeaturesOperation {
    pub(super) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        hir_dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let flags = graph.u32_buffer("semantic_feature_flags")?;
        Ok(Self {
            clear: crate::gpu::operations::ClearBufferOperation::entire(
                graph,
                compiler_graph::FEATURES_CLEAR_PASS,
                "semantic_feature_flags",
                &flags,
            )?,
            collect: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::FEATURES_COLLECT_PASS,
                &passes.kernel("type_checker/semantic/features/00_collect"),
                hir_dispatch_args,
            )?,
            dispatch: ComputeOperation::direct(
                device,
                graph,
                resources,
                compiler_graph::FEATURES_DISPATCH_PASS,
                &passes.kernel("type_checker/semantic/features/01_dispatch_args"),
                1,
            )?,
        })
    }

    pub(super) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder);
        self.collect.record(encoder)?;
        self.dispatch.record(encoder)
    }
}
