//! One reflected compute shader as an executable compiler operation.

use anyhow::Result;

use super::{record_direct_with_offsets, record_indirect_at};
use crate::gpu::{
    buffers::LaniusBuffer,
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        INDIRECT_DISPATCH_BINDING,
        MaterializedCompilerGraph,
        ReflectedComputeSpec,
    },
    passes_core::{ComputePassBatch, PassData},
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

impl ComputeGraph for MaterializedCompilerGraph {
    fn graph(&self) -> &CompilerGraph {
        MaterializedCompilerGraph::graph(self)
    }

    fn allocations(&self) -> &CompilerGraphAllocations {
        MaterializedCompilerGraph::allocations(self)
    }
}

/// Resolves the stable shader key carried by a reflected operation spec.
pub(crate) trait ComputeKernels {
    fn kernel(&self, key: &str) -> &PassData;
}

enum Dispatch {
    Direct {
        elements: u32,
        dynamic_offsets: Vec<u32>,
    },
    Indirect {
        args: LaniusBuffer<u32>,
        offset: u64,
    },
}

/// A shader, its reflection-built bindings, validated ownership, and dispatch.
pub(crate) struct ComputeOperation {
    name: &'static str,
    pass: PassData,
    group: wgpu::BindGroup,
    dispatch: Dispatch,
    bindings: Vec<BoundGraphResource>,
}

/// One additional semantic position at which a materialized compute operation
/// is invoked. Creation proves that the target graph node uses the same shader,
/// resources, and physical allocation ranges; recording then reuses the
/// existing pipeline and bind group without adding warm-job setup work.
pub(crate) struct ComputeInvocation {
    name: &'static str,
    shader_id: String,
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
        let pass_desc = core.pass(pass_id).expect("pass id came from graph");
        let indirect_access = pass_desc
            .accesses
            .iter()
            .find(|access| access.binding == INDIRECT_DISPATCH_BINDING);
        if let (Dispatch::Indirect { args, .. }, Some(access)) = (&dispatch, indirect_access) {
            let canonical = core
                .resource(access.resource)
                .expect("pass resource came from graph")
                .name;
            resources.buffer(canonical, args);
        }
        for access in &pass_desc.accesses {
            let canonical = core
                .resource(access.resource)
                .expect("pass resource came from graph")
                .name;
            resources.alias(access.binding, canonical)?;
        }
        let mut bindings = resources.graph_bindings(core, name)?;
        match (&dispatch, indirect_access) {
            (Dispatch::Indirect { args, .. }, Some(access)) => {
                let actual =
                    BoundGraphResource::buffer(INDIRECT_DISPATCH_BINDING, access.resource, args)
                        .map_err(anyhow::Error::msg)?;
                let expected = bindings
                    .iter_mut()
                    .find(|bound| {
                        bound.binding == INDIRECT_DISPATCH_BINDING
                            && bound.resource == access.resource
                    })
                    .expect("graph bindings include every pass access");
                *expected = actual;
            }
            (Dispatch::Direct { .. }, Some(_)) => {
                return Err(anyhow::anyhow!(
                    "compiler operation `{name}` declares indirect dispatch but was constructed as direct",
                ));
            }
            (Dispatch::Indirect { .. }, None) => {
                return Err(anyhow::anyhow!(
                    "compiler operation `{name}` uses indirect dispatch without declaring its dispatch-argument resource in the compiler graph",
                ));
            }
            (Dispatch::Direct { .. }, None) => {}
        }
        graph
            .allocations()
            .validate_pass_bindings(core, pass_id, &bindings)
            .map_err(anyhow::Error::msg)?;
        Ok(Self {
            name,
            pass: pass.clone(),
            group: reflected_bind_group_from_resources(device, name, pass, &resources)?,
            dispatch,
            bindings,
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
            Dispatch::Direct {
                elements,
                dynamic_offsets: Vec::new(),
            },
        )
    }

    /// Builds a direct operation selecting one or more rows from dynamic
    /// uniform tables. Offsets are fixed with the bind group, so recording
    /// remains allocation-free.
    pub(crate) fn direct_with_offsets(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        elements: u32,
        dynamic_offsets: Vec<u32>,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            Dispatch::Direct {
                elements,
                dynamic_offsets,
            },
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
        dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            Dispatch::Indirect {
                args: dispatch_args.clone(),
                offset: 0,
            },
        )
    }

    pub(crate) fn indirect_at(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        dispatch_args: &LaniusBuffer<u32>,
        offset: u64,
    ) -> Result<Self> {
        Self::new(
            device,
            graph,
            resources,
            name,
            pass,
            Dispatch::Indirect {
                args: dispatch_args.clone(),
                offset,
            },
        )
    }

    pub(crate) fn indirect_spec_at(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        kernels: &impl ComputeKernels,
        spec: ReflectedComputeSpec,
        dispatch_args: &LaniusBuffer<u32>,
        offset: u64,
    ) -> Result<Self> {
        Self::indirect_at(
            device,
            graph,
            resources,
            spec.name,
            kernels.kernel(spec.kernel),
            dispatch_args,
            offset,
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
        dispatch_args: &LaniusBuffer<u32>,
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
        self.record_as(encoder, self.name)
    }

    /// Records a direct operation for a smaller active domain than the
    /// capacity used to build its stable pipeline and bind group.
    pub(crate) fn record_elements(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        elements: u32,
    ) -> Result<()> {
        match &self.dispatch {
            Dispatch::Direct {
                elements: capacity,
                dynamic_offsets,
            } => {
                if elements > *capacity {
                    return Err(anyhow::anyhow!(
                        "compiler operation `{}` requested {elements} elements beyond its {capacity}-element capacity",
                        self.name,
                    ));
                }
                record_direct_with_offsets(
                    encoder,
                    &self.pass,
                    &self.group,
                    self.name,
                    elements,
                    dynamic_offsets,
                )
            }
            Dispatch::Indirect { .. } => Err(anyhow::anyhow!(
                "compiler operation `{}` is indirect and cannot override its element count",
                self.name,
            )),
        }
    }

    /// Records two compatible graph operations in one physical compute pass.
    /// Their graph identities remain distinct for schedule telemetry and
    /// lifetime validation while avoiding an otherwise redundant pass boundary.
    pub(crate) fn record_pair(
        first: &Self,
        second: &Self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        if crate::gpu::timer::operation_capture_requires_split_passes() {
            first.record(encoder)?;
            return second.record(encoder);
        }
        let mut batch = ComputePassBatch::begin_graph_operation(encoder, first.name);
        first.record_into_batch(&mut batch)?;
        batch.begin_next_graph_operation(second.name);
        second.record_into_batch(&mut batch)
    }

    fn record_into_batch<'a>(&'a self, batch: &mut ComputePassBatch<'a>) -> Result<()> {
        match &self.dispatch {
            Dispatch::Direct {
                elements,
                dynamic_offsets,
            } => batch.record_raw_with_offsets(&self.pass, &self.group, *elements, dynamic_offsets),
            Dispatch::Indirect { args, offset } => {
                batch.record_buffer_indirect_at_with_offsets(
                    &self.pass,
                    &self.group,
                    args,
                    *offset,
                    &[],
                );
                Ok(())
            }
        }
    }

    pub(crate) fn invocation(
        &self,
        graph: &impl ComputeGraph,
        name: &'static str,
    ) -> Result<ComputeInvocation> {
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let expected_kernel = core.pass_kernel(pass).ok_or_else(|| {
            anyhow::anyhow!("compiler graph pass `{name}` has no assigned compute kernel")
        })?;
        if expected_kernel != self.pass.shader_id {
            return Err(anyhow::anyhow!(
                "compiler graph invocation `{name}` uses kernel `{expected_kernel}`, but the materialized operation uses `{}`",
                self.pass.shader_id,
            ));
        }
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &self.bindings)
            .map_err(anyhow::Error::msg)?;
        Ok(ComputeInvocation {
            name,
            shader_id: self.pass.shader_id.clone(),
        })
    }

    pub(crate) fn record_invocation(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        invocation: &ComputeInvocation,
    ) -> Result<()> {
        if invocation.shader_id != self.pass.shader_id {
            return Err(anyhow::anyhow!(
                "compiler invocation `{}` belongs to kernel `{}`, not `{}`",
                invocation.name,
                invocation.shader_id,
                self.pass.shader_id,
            ));
        }
        self.record_as(encoder, invocation.name)
    }

    pub(crate) fn record_as(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        operation_name: &'static str,
    ) -> Result<()> {
        match &self.dispatch {
            Dispatch::Direct {
                elements,
                dynamic_offsets,
            } => record_direct_with_offsets(
                encoder,
                &self.pass,
                &self.group,
                operation_name,
                *elements,
                dynamic_offsets,
            ),
            Dispatch::Indirect { args, offset } => record_indirect_at(
                encoder,
                &self.pass,
                &self.group,
                operation_name,
                args,
                *offset,
            ),
        }
    }
}
