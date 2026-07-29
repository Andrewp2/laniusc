//! Reusable GPU-parallel operations used to assemble semantic passes.

mod call_argument_matching;
mod call_claim_keys;
mod call_generic_claim_validation;
mod calls;
mod generic_parameter_sorts;
mod hierarchical_radix_sort;
mod methods;
mod predicate_keys;
mod prefix_scan;
mod radix_sort;
mod visible_decls;

pub(super) use call_argument_matching::*;
pub(super) use call_claim_keys::*;
pub(super) use call_generic_claim_validation::*;
pub(super) use calls::*;
pub(super) use generic_parameter_sorts::*;
pub(super) use hierarchical_radix_sort::*;
pub(super) use methods::*;
pub(super) use predicate_keys::*;
pub(super) use prefix_scan::*;
pub(super) use radix_sort::*;
pub(super) use visible_decls::*;

use super::*;

enum ComputeDispatch {
    Direct(u32),
    Indirect(wgpu::Buffer),
}

/// One reflected shader together with its validated resources and dispatch.
pub(super) struct ComputeOperation {
    name: &'static str,
    pass: PassData,
    group: wgpu::BindGroup,
    dispatch: ComputeDispatch,
}

impl ComputeOperation {
    fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        dispatch: ComputeDispatch,
    ) -> Result<Self> {
        graph.validate_registered_pass_bindings(name, resources)?;
        Ok(Self {
            name,
            pass: pass.clone(),
            group: reflected_bind_group_from_resources(device, name, pass, resources)?,
            dispatch,
        })
    }

    pub(super) fn direct(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        workgroups: u32,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            ComputeDispatch::Direct(workgroups),
        )
    }

    pub(super) fn indirect(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            ComputeDispatch::Indirect(dispatch_args.clone()),
        )
    }

    pub(super) fn indirect_spec(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
        pass: &PassData,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<Self> {
        Self::indirect(device, graph, resources, spec.name, pass, dispatch_args)
    }

    pub(super) fn direct_spec(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
        pass: &PassData,
        workgroups: u32,
    ) -> Result<Self> {
        Self::direct(device, graph, resources, spec.name, pass, workgroups)
    }

    pub(super) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        match &self.dispatch {
            ComputeDispatch::Direct(workgroups) => {
                record_compute(encoder, &self.pass, &self.group, self.name, *workgroups)
            }
            ComputeDispatch::Indirect(args) => {
                record_compute_indirect(encoder, &self.pass, &self.group, self.name, args)
            }
        }
    }
}

/// Discovers which optional semantic pass groups are needed by a job and
/// writes their indirect dispatch arguments. Reflection supplies the graph
/// access surface and bind-group surface; this value owns the executable
/// schedule so the resident recorder cannot reproduce it independently.
pub(super) struct SemanticFeaturesOperation {
    flags: LaniusBuffer<u32>,
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
        graph.validate_registered_pass_bindings(compiler_graph::FEATURES_CLEAR_PASS, resources)?;
        Ok(Self {
            flags: graph.u32_buffer("semantic_feature_flags")?,
            collect: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::FEATURES_COLLECT_PASS,
                &passes.semantic_features_collect,
                hir_dispatch_args,
            )?,
            dispatch: ComputeOperation::direct(
                device,
                graph,
                resources,
                compiler_graph::FEATURES_DISPATCH_PASS,
                &passes.semantic_features_dispatch_args,
                1,
            )?,
        })
    }

    pub(super) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_typecheck_clear_buffer(encoder, &self.flags, 0, Some(4));
        self.collect.record(encoder)?;
        self.dispatch.record(encoder)
    }
}
