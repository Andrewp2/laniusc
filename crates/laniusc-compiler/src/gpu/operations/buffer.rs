//! Graph-validated non-shader buffer operations.

use anyhow::Result;

use super::ComputeGraph;
use crate::gpu::{
    buffers::{JobResetPolicy, LaniusBuffer, ResettableBuffer, TrackedBufferView},
    compiler_graph::BoundGraphResource,
    passes_core::record_compiler_operation,
    resource_registry::ResourceMap,
};

/// Clears one complete graph resource without hiding the write from liveness
/// analysis. Construction proves that the concrete buffer is the allocation
/// selected for the named graph pass.
pub(crate) struct ClearBufferOperation {
    name: &'static str,
    buffer: LaniusBuffer<u8>,
}

/// Clears several graph resources as one declared compiler operation. The
/// resources may share a physical arena, but their logical byte windows must
/// not overlap while simultaneously writable.
pub(crate) struct ClearBuffersOperation {
    name: &'static str,
    buffers: Vec<LaniusBuffer<u8>>,
}

impl ClearBuffersOperation {
    pub(crate) fn new(
        graph: &impl ComputeGraph,
        name: &'static str,
        buffers: &[(&'static str, TrackedBufferView<'_>)],
    ) -> Result<Self> {
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let pass_desc = core.pass(pass).expect("pass id came from graph");
        let owned_buffers = buffers
            .iter()
            .map(|(_, buffer)| buffer.alias::<u8>(buffer.byte_size as usize))
            .collect::<Vec<_>>();
        let mut bindings = Vec::with_capacity(buffers.len());
        for ((binding, _), buffer) in buffers.iter().zip(&owned_buffers) {
            let access = pass_desc
                .accesses
                .iter()
                .find(|access| access.binding == *binding)
                .ok_or_else(|| {
                    anyhow::anyhow!("compiler graph pass `{name}` has no binding `{binding}`")
                })?;
            if !access.mode.writes() {
                return Err(anyhow::anyhow!(
                    "compiler graph pass `{name}` does not write `{binding}`"
                ));
            }
            bindings.push(
                BoundGraphResource::buffer(binding, access.resource, buffer)
                    .map_err(anyhow::Error::msg)?,
            );
        }
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &bindings)
            .map_err(anyhow::Error::msg)?;

        for (left_index, (_, left)) in buffers.iter().enumerate() {
            for (_, right) in &buffers[left_index + 1..] {
                if left.allocation_id().is_some()
                    && left.allocation_id() == right.allocation_id()
                    && left.byte_offset < right.byte_offset + right.byte_size
                    && right.byte_offset < left.byte_offset + left.byte_size
                {
                    return Err(anyhow::anyhow!(
                        "compiler clear `{name}` binds overlapping writable allocation ranges"
                    ));
                }
            }
        }

        Ok(Self {
            name,
            buffers: owned_buffers,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        for buffer in &self.buffers {
            encoder.clear_buffer(
                &buffer.buffer,
                buffer.byte_offset,
                Some(buffer.byte_size as u64),
            );
        }
    }
}

/// Publishes one or more empty count-bounded relations. Only the scalar count
/// headers need physical zeroing; member rows have no observable values while
/// their counts are zero. The graph still sees every member as initialized at
/// this exact schedule point, preserving accurate lifetimes without clearing
/// capacity-sized arrays.
pub(crate) struct EmptyRelationsOperation {
    name: &'static str,
    count_headers: Vec<LaniusBuffer<u8>>,
}

/// Resets the graph's reusable physical allocations before a job without
/// treating the reset as a logical producer for every colored resource packed
/// into those allocations.
pub(crate) struct ResetGraphAllocationsOperation {
    name: &'static str,
    allocations: Vec<LaniusBuffer<u8>>,
}

impl ResetGraphAllocationsOperation {
    pub(crate) fn new(
        graph: &impl ComputeGraph,
        name: &'static str,
        buffers: &[ResettableBuffer],
    ) -> Result<Self> {
        if graph.graph().pass_id(name).is_none() {
            return Err(anyhow::anyhow!("compiler graph has no pass `{name}`"));
        }
        let mut allocations = Vec::new();
        for buffer in buffers {
            if buffer.reset_policy == JobResetPolicy::OverwriteBeforeRead {
                continue;
            }
            if !graph.allocations().owns_allocation(buffer.allocation_id) {
                return Err(anyhow::anyhow!(
                    "compiler graph reset `{name}` received non-graph allocation `{}` ({})",
                    buffer.label,
                    buffer.allocation_id,
                ));
            }
            allocations.push(buffer.tracked_view().alias(buffer.byte_size as usize));
        }
        Ok(Self { name, allocations })
    }

    /// Creates a physical job-boundary reset for allocations owned by the
    /// surrounding phase object rather than by the graph workspace itself.
    /// The reset is allocation-scoped and therefore intentionally does not
    /// pretend to produce every logical graph resource that aliases it.
    pub(crate) fn new_tracked(
        graph: &impl ComputeGraph,
        name: &'static str,
        buffers: &[ResettableBuffer],
    ) -> Result<Self> {
        if graph.graph().pass_id(name).is_none() {
            return Err(anyhow::anyhow!("compiler graph has no pass `{name}`"));
        }
        let allocations = buffers
            .iter()
            .map(|buffer| buffer.tracked_view().alias::<u8>(buffer.byte_size as usize))
            .collect();
        Ok(Self { name, allocations })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        for buffer in &self.allocations {
            encoder.clear_buffer(&buffer.buffer, 0, None);
        }
    }

    /// Resets an active prefix of each allocation. This preserves capacity-
    /// based reuse without writing inactive rows of a large resident parser
    /// workspace on every smaller job.
    pub(crate) fn record_ranges<I>(&self, encoder: &mut wgpu::CommandEncoder, byte_sizes: I) -> u64
    where
        I: IntoIterator<Item = u64>,
    {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        let mut cleared = 0u64;
        let mut byte_sizes = byte_sizes.into_iter();
        for buffer in &self.allocations {
            let byte_size = byte_sizes
                .next()
                .expect("compiler reset range count does not match its allocation set");
            assert!(
                byte_size <= buffer.byte_size as u64,
                "compiler reset range exceeds its allocation"
            );
            if byte_size == 0 {
                continue;
            }
            assert_eq!(
                byte_size % wgpu::COPY_BUFFER_ALIGNMENT,
                0,
                "compiler reset range is not copy-aligned"
            );
            encoder.clear_buffer(&buffer.buffer, 0, Some(byte_size));
            cleared = cleared.saturating_add(byte_size);
        }
        assert!(
            byte_sizes.next().is_none(),
            "compiler reset range count does not match its allocation set"
        );
        cleared
    }
}

impl EmptyRelationsOperation {
    pub(crate) fn new(
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        count_headers: &[&'static str],
        members: &[&'static str],
    ) -> Result<Self> {
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let pass_desc = core.pass(pass).expect("pass id came from graph");
        let names = count_headers
            .iter()
            .chain(members)
            .copied()
            .collect::<Vec<_>>();
        let views = names
            .iter()
            .map(|name| {
                let access = pass_desc
                    .accesses
                    .iter()
                    .find(|access| access.binding == *name)
                    .ok_or_else(|| {
                        anyhow::anyhow!("compiler graph pass `{name}` has no binding `{name}`")
                    })?;
                let bytes = core
                    .resource(access.resource)
                    .expect("pass resource id came from graph")
                    .bytes;
                resources
                    .tracked_view(name)?
                    .subrange(0, bytes)
                    .map_err(anyhow::Error::msg)
            })
            .collect::<Result<Vec<_>>>()?;
        let owned = views
            .iter()
            .map(|view| view.alias::<u8>(view.byte_size as usize))
            .collect::<Vec<_>>();
        let mut bindings = Vec::with_capacity(names.len());
        for ((binding, buffer), view) in names.iter().zip(&owned).zip(&views) {
            let access = pass_desc
                .accesses
                .iter()
                .find(|access| access.binding == *binding)
                .ok_or_else(|| {
                    anyhow::anyhow!("compiler graph pass `{name}` has no binding `{binding}`")
                })?;
            if !access.mode.writes() {
                return Err(anyhow::anyhow!(
                    "compiler graph pass `{name}` does not write `{binding}`"
                ));
            }
            debug_assert_eq!(buffer.byte_offset, view.byte_offset);
            bindings.push(
                BoundGraphResource::buffer(binding, access.resource, buffer)
                    .map_err(anyhow::Error::msg)?,
            );
        }
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &bindings)
            .map_err(anyhow::Error::msg)?;

        Ok(Self {
            name,
            count_headers: owned.into_iter().take(count_headers.len()).collect(),
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        for count in &self.count_headers {
            debug_assert_eq!(count.byte_size, std::mem::size_of::<u32>());
            encoder.clear_buffer(
                &count.buffer,
                count.byte_offset,
                Some(count.byte_size as u64),
            );
        }
    }
}

impl ClearBufferOperation {
    pub(crate) fn entire<T>(
        graph: &impl ComputeGraph,
        name: &'static str,
        binding: &'static str,
        buffer: &LaniusBuffer<T>,
    ) -> Result<Self> {
        Self::range(graph, name, binding, buffer, 0, buffer.byte_size as u64)
    }

    pub(crate) fn range<T>(
        graph: &impl ComputeGraph,
        name: &'static str,
        binding: &'static str,
        buffer: &LaniusBuffer<T>,
        byte_offset: u64,
        byte_size: u64,
    ) -> Result<Self> {
        let buffer = TrackedBufferView::from(buffer)
            .subrange(byte_offset, byte_size)
            .map_err(anyhow::Error::msg)?
            .alias::<u8>(byte_size as usize);
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let access = core
            .pass(pass)
            .expect("pass id came from graph")
            .accesses
            .iter()
            .find(|access| access.binding == binding)
            .ok_or_else(|| {
                anyhow::anyhow!("compiler graph pass `{name}` has no binding `{binding}`")
            })?;
        if !access.mode.writes() {
            return Err(anyhow::anyhow!(
                "compiler graph pass `{name}` does not write `{binding}`"
            ));
        }
        let bound = BoundGraphResource::buffer(binding, access.resource, &buffer)
            .map_err(anyhow::Error::msg)?;
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &[bound])
            .map_err(anyhow::Error::msg)?;
        Ok(Self { name, buffer })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        encoder.clear_buffer(
            &self.buffer.buffer,
            self.buffer.byte_offset,
            Some(self.buffer.byte_size as u64),
        );
    }
}

/// One graph-validated GPU buffer copy. Offsets describe the physical copy,
/// while graph validation uses each buffer's complete logical allocation.
pub(crate) struct CopyBufferOperation {
    name: &'static str,
    source: wgpu::Buffer,
    source_base_offset: u64,
    _source_owner: Option<LaniusBuffer<u8>>,
    source_offset: u64,
    destination: LaniusBuffer<u8>,
    destination_offset: u64,
    size: u64,
}

/// One graph operation containing several independent buffer copies.
/// Ping-pong finalizers use this to publish all columns together without
/// recreating per-job ownership metadata or hand-recording raw copies.
pub(crate) struct CopyBuffersOperation {
    name: &'static str,
    copies: Vec<(LaniusBuffer<u8>, LaniusBuffer<u8>, u64)>,
}

impl CopyBuffersOperation {
    pub(crate) fn prefixes(
        graph: &impl ComputeGraph,
        name: &'static str,
        copies: &[(
            &'static str,
            TrackedBufferView<'_>,
            &'static str,
            TrackedBufferView<'_>,
            u64,
        )],
    ) -> Result<Self> {
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let pass_desc = core.pass(pass).expect("pass id came from graph");
        let mut owned = Vec::with_capacity(copies.len());
        let mut bindings = Vec::with_capacity(copies.len() * 2);
        let mut bound_allocations = std::collections::HashMap::new();
        for &(source_binding, source, destination_binding, destination, size) in copies {
            if size > source.byte_size || size > destination.byte_size {
                return Err(anyhow::anyhow!(
                    "compiler copy `{name}` exceeds its source or destination prefix"
                ));
            }
            let source_access = pass_desc
                .accesses
                .iter()
                .find(|access| access.binding == source_binding)
                .ok_or_else(|| {
                    anyhow::anyhow!("compiler graph pass `{name}` has no source `{source_binding}`")
                })?;
            let destination_access = pass_desc
                .accesses
                .iter()
                .find(|access| access.binding == destination_binding)
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "compiler graph pass `{name}` has no destination `{destination_binding}`"
                    )
                })?;
            if source_access.mode.writes() || !destination_access.mode.writes() {
                return Err(anyhow::anyhow!(
                    "compiler graph pass `{name}` does not declare read sources and write destinations"
                ));
            }
            let source = source.alias::<u8>(source.byte_size as usize);
            let destination = destination.alias::<u8>(destination.byte_size as usize);
            for (binding, resource, buffer) in [
                (source_binding, source_access.resource, &source),
                (
                    destination_binding,
                    destination_access.resource,
                    &destination,
                ),
            ] {
                if let Some(&(bound_resource, allocation)) = bound_allocations.get(binding) {
                    if bound_resource != resource || allocation != buffer.allocation_id() {
                        return Err(anyhow::anyhow!(
                            "compiler copy `{name}` binds `{binding}` to inconsistent resources"
                        ));
                    }
                    continue;
                }
                bound_allocations.insert(binding, (resource, buffer.allocation_id()));
                bindings.push(
                    BoundGraphResource::buffer(binding, resource, buffer)
                        .map_err(anyhow::Error::msg)?,
                );
            }
            owned.push((source, destination, size));
        }
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &bindings)
            .map_err(anyhow::Error::msg)?;
        Ok(Self {
            name,
            copies: owned,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        for (source, destination, size) in &self.copies {
            encoder.copy_buffer_to_buffer(
                &source.buffer,
                source.byte_offset,
                &destination.buffer,
                destination.byte_offset,
                *size,
            );
        }
    }
}

impl CopyBufferOperation {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new<S, D>(
        graph: &impl ComputeGraph,
        name: &'static str,
        source_binding: &'static str,
        source: &LaniusBuffer<S>,
        source_offset: u64,
        destination_binding: &'static str,
        destination: &LaniusBuffer<D>,
        destination_offset: u64,
        size: u64,
    ) -> Result<Self> {
        let source_end = source_offset
            .checked_add(size)
            .ok_or_else(|| anyhow::anyhow!("compiler copy `{name}` source range overflows"))?;
        let destination_end = destination_offset
            .checked_add(size)
            .ok_or_else(|| anyhow::anyhow!("compiler copy `{name}` destination range overflows"))?;
        if source_end > source.byte_size as u64 || destination_end > destination.byte_size as u64 {
            return Err(anyhow::anyhow!(
                "compiler copy `{name}` range exceeds its source or destination buffer"
            ));
        }
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let pass_desc = core.pass(pass).expect("pass id came from graph");
        let source_access = pass_desc
            .accesses
            .iter()
            .find(|access| access.binding == source_binding)
            .ok_or_else(|| {
                anyhow::anyhow!("compiler graph pass `{name}` has no source `{source_binding}`")
            })?;
        let destination_access = pass_desc
            .accesses
            .iter()
            .find(|access| access.binding == destination_binding)
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "compiler graph pass `{name}` has no destination `{destination_binding}`"
                )
            })?;
        if source_access.mode.writes() || !destination_access.mode.writes() {
            return Err(anyhow::anyhow!(
                "compiler graph pass `{name}` does not declare a read source and write destination"
            ));
        }
        let bindings = [
            BoundGraphResource::buffer(source_binding, source_access.resource, source)
                .map_err(anyhow::Error::msg)?,
            BoundGraphResource::buffer(
                destination_binding,
                destination_access.resource,
                destination,
            )
            .map_err(anyhow::Error::msg)?,
        ];
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &bindings)
            .map_err(anyhow::Error::msg)?;
        let source_owner = source.alias(source.byte_size);
        Ok(Self {
            name,
            source: source_owner.buffer.clone(),
            source_base_offset: source_owner.byte_offset,
            _source_owner: Some(source_owner),
            source_offset,
            destination: destination.alias(destination.byte_size),
            destination_offset,
            size,
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_external_input<D>(
        graph: &impl ComputeGraph,
        name: &'static str,
        source_binding: &'static str,
        source: &wgpu::Buffer,
        source_offset: u64,
        destination_binding: &'static str,
        destination: &LaniusBuffer<D>,
        destination_offset: u64,
        size: u64,
    ) -> Result<Self> {
        let source_end = source_offset
            .checked_add(size)
            .ok_or_else(|| anyhow::anyhow!("compiler copy `{name}` source range overflows"))?;
        let destination_end = destination_offset
            .checked_add(size)
            .ok_or_else(|| anyhow::anyhow!("compiler copy `{name}` destination range overflows"))?;
        if source_end > source.size() || destination_end > destination.byte_size as u64 {
            return Err(anyhow::anyhow!(
                "compiler copy `{name}` range exceeds its source or destination buffer"
            ));
        }
        let core = graph.graph();
        let pass = core
            .pass_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{name}`"))?;
        let pass_desc = core.pass(pass).expect("pass id came from graph");
        let source_access = pass_desc
            .accesses
            .iter()
            .find(|access| access.binding == source_binding)
            .ok_or_else(|| {
                anyhow::anyhow!("compiler graph pass `{name}` has no source `{source_binding}`")
            })?;
        let destination_access = pass_desc
            .accesses
            .iter()
            .find(|access| access.binding == destination_binding)
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "compiler graph pass `{name}` has no destination `{destination_binding}`"
                )
            })?;
        if source_access.mode.writes() || !destination_access.mode.writes() {
            return Err(anyhow::anyhow!(
                "compiler graph pass `{name}` does not declare a read source and write destination"
            ));
        }
        let bindings = [
            core.bind_external_input(source_binding, source_access.resource, source)
                .map_err(anyhow::Error::msg)?,
            BoundGraphResource::buffer(
                destination_binding,
                destination_access.resource,
                destination,
            )
            .map_err(anyhow::Error::msg)?,
        ];
        graph
            .allocations()
            .validate_pass_bindings(core, pass, &bindings)
            .map_err(anyhow::Error::msg)?;
        Ok(Self {
            name,
            source: source.clone(),
            source_base_offset: 0,
            _source_owner: None,
            source_offset,
            destination: destination.alias(destination.byte_size),
            destination_offset,
            size,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        self.record_size(encoder, self.size);
    }

    /// Records an active prefix of a capacity-sized copy operation. This lets
    /// daemon jobs retain the graph validation and buffer identities while
    /// varying only the number of rows copied by the current request.
    pub(crate) fn record_size(&self, encoder: &mut wgpu::CommandEncoder, size: u64) {
        assert!(
            size <= self.size,
            "compiler copy active range exceeds its validated capacity"
        );
        if size == 0 {
            return;
        }
        record_compiler_operation(self.name);
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        encoder.copy_buffer_to_buffer(
            &self.source,
            self.source_base_offset + self.source_offset,
            &self.destination.buffer,
            self.destination.byte_offset + self.destination_offset,
            size,
        );
    }
}
