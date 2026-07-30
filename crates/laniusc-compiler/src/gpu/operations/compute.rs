//! One reflected compute shader as an executable compiler operation.

use anyhow::Result;

use super::{record_direct, record_indirect};
use crate::gpu::{
    buffers::LaniusBuffer,
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, ReflectedComputeSpec},
    passes_core::PassData,
    resource_registry::{ResourceMap, reflected_bind_group_from_resources},
};

/// Supplies the graph and allocation identities used to validate an operation.
pub(crate) trait ComputeGraph {
    fn graph(&self) -> &CompilerGraph;
    fn allocations(&self) -> &CompilerGraphAllocations;
}

impl ComputeGraph for (&CompilerGraph, &CompilerGraphAllocations) {
    fn graph(&self) -> &CompilerGraph {
        self.0
    }

    fn allocations(&self) -> &CompilerGraphAllocations {
        self.1
    }
}

/// Resolves the stable shader key carried by a reflected operation spec.
pub(crate) trait ComputeKernels {
    fn kernel(&self, key: &str) -> &PassData;
}

enum Dispatch {
    Direct(u32),
    Indirect(wgpu::Buffer),
}

/// A shader, its reflection-built bindings, validated ownership, and dispatch.
pub(crate) struct ComputeOperation {
    name: &'static str,
    pass: PassData,
    group: wgpu::BindGroup,
    dispatch: Dispatch,
}

impl ComputeOperation {
    fn new(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        dispatch: Dispatch,
    ) -> Result<Self> {
        let core = graph.graph();
        let pass_id = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let mut resources = resources.clone();
        for access in &core
            .pass(pass_id)
            .expect("pass id came from graph")
            .accesses
        {
            let canonical = core
                .resource(access.resource)
                .expect("pass resource came from graph")
                .name;
            resources.alias(access.binding, canonical)?;
        }
        let bindings = resources.graph_bindings(core, name)?;
        graph
            .allocations()
            .validate_pass_bindings(core, pass_id, &bindings)
            .map_err(anyhow::Error::msg)?;
        Ok(Self {
            name,
            pass: pass.clone(),
            group: reflected_bind_group_from_resources(device, name, pass, &resources)?,
            dispatch,
        })
    }

    pub(crate) fn direct(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        elements: u32,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            Dispatch::Direct(elements),
        )
    }

    /// Builds a direct operation whose only non-graph binding is its uniform
    /// parameter buffer.
    pub(crate) fn direct_with_uniform<T>(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        params: &LaniusBuffer<T>,
        elements: u32,
    ) -> Result<Self> {
        let mut resources = resources.clone();
        resources.buffer("gParams", params);
        Self::direct(device, graph, &resources, name, pass, elements)
    }

    pub(crate) fn indirect(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
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
            Dispatch::Indirect(dispatch_args.clone()),
        )
    }

    pub(crate) fn direct_spec(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        kernels: &impl ComputeKernels,
        spec: ReflectedComputeSpec,
        elements: u32,
    ) -> Result<Self> {
        Self::direct(
            device,
            graph,
            resources,
            spec.name,
            kernels.kernel(spec.kernel),
            elements,
        )
    }

    pub(crate) fn indirect_spec(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        kernels: &impl ComputeKernels,
        spec: ReflectedComputeSpec,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<Self> {
        Self::indirect(
            device,
            graph,
            resources,
            spec.name,
            kernels.kernel(spec.kernel),
            dispatch_args,
        )
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        match &self.dispatch {
            Dispatch::Direct(elements) => {
                record_direct(encoder, &self.pass, &self.group, self.name, *elements)
            }
            Dispatch::Indirect(args) => {
                record_indirect(encoder, &self.pass, &self.group, self.name, args)
            }
        }
    }
}
