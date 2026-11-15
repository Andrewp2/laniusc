//! Solver proof bindings become closed method environments on the GPU.
use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail};

use super::{
    ProgramRetention,
    Store,
    counts,
    grown_capacity,
    reflected_names,
    storage,
    substitution::Publication,
    words_bytes,
};
use crate::{
    compiler::{ClosedTraitPublication, RetainedTraitPublication, RetainedTraitView},
    gpu::passes_core::{self, PassData, make_pass_data_from_shader_key},
};
const KEYS: [&str; 7] = [
    "type_checker/retention/method_routes/00_begin",
    "type_checker/retention/method_routes/01_select",
    "type_checker/retention/method_routes/02_expand",
    "type_checker/retention/method_routes/03_terms",
    "type_checker/retention/method_routes/04_environments",
    "type_checker/retention/method_routes/05_finish",
    "type_checker/retention/method_routes/06_rollback",
];

pub(super) struct MethodRoutes {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    configs: Vec<wgpu::Buffer>,
}
impl MethodRoutes {
    pub fn new_with_device(gpu: &crate::gpu::device::GpuDevice) -> Result<Self> {
        let passes = KEYS
            .iter()
            .map(|name| {
                let key = *name;
                make_pass_data_from_shader_key(&gpu.device, key, "main", key)
            })
            .collect::<Result<_>>()?;
        Ok(Self {
            device: gpu.device.clone(),
            queue: gpu.queue.clone(),
            passes,
            buffers: BTreeMap::new(),
            configs: Vec::new(),
        })
    }
    pub fn output(&self) -> &wgpu::Buffer {
        &self.buffers["mr_out"]
    }
    fn ensure(&mut self, name: &'static str, bytes: u64) -> Result<()> {
        let limits = self.device.limits();
        if bytes > limits.max_buffer_size
            || bytes > u64::from(limits.max_storage_buffer_binding_size)
        {
            bail!("method routes {name} exceeds device capacity");
        }
        if self.buffers.get(name).is_none_or(|b| b.size() < bytes) {
            self.buffers
                .insert(name, storage(&self.device, name, bytes.max(4), false));
        }
        Ok(())
    }
    pub fn run(
        &mut self,
        store: &ProgramRetention,
        source: &RetainedTraitPublication,
        closed: &ClosedTraitPublication,
        sub: &Publication<'_>,
        metadata: &wgpu::Buffer,
        instances: &wgpu::Buffer,
    ) -> Result<Vec<u32>> {
        let view = closed.view(source, store)?;
        let nodes = closed.proof_node_count();
        let requests = sub.id.requests;
        for (name, bytes) in [
            ("mr_state", 128),
            ("mr_selected", u64::from(requests.max(1)) * 16),
            ("mr_reach", u64::from(nodes.max(1)) * 4),
            ("mr_values_a", u64::from(nodes.max(1)) * 4),
            ("mr_values_b", u64::from(nodes.max(1)) * 4),
            ("mr_args", u64::from(requests.max(1)) * 64 * 4),
            ("mr_out", u64::from(requests.max(1)) * 16),
        ] {
            self.ensure(name, bytes)?;
        }
        if self.configs.is_empty() {
            for _ in 0..2 {
                self.configs
                    .push(storage(&self.device, "mr_config", 40, false));
            }
        }
        let id = view.identity;
        for parity in 0..2 {
            let config = [
                sub.id.run,
                sub.id.generation,
                requests,
                nodes,
                parity as u32,
                id.epoch as u32,
                (id.epoch >> 32) as u32,
                id.arena_id as u32,
                (id.arena_id >> 32) as u32,
                id.serial,
            ];
            self.queue
                .write_buffer(&self.configs[parity], 0, &words_bytes(&config));
        }
        let mut guard = store.store.lock().unwrap();
        let result = (|| {
            loop {
                let mut encoder = self.device.create_command_encoder(&Default::default());
                self.record(
                    &mut encoder,
                    0,
                    requests.max(nodes).max(1),
                    0,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                self.record(
                    &mut encoder,
                    1,
                    requests,
                    0,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                for _ in 0..65 {
                    self.record(
                        &mut encoder,
                        2,
                        nodes,
                        0,
                        &guard,
                        &view,
                        sub,
                        metadata,
                        instances,
                    )?;
                }
                for round in 0..65 {
                    self.record(
                        &mut encoder,
                        3,
                        nodes,
                        round % 2,
                        &guard,
                        &view,
                        sub,
                        metadata,
                        instances,
                    )?;
                }
                self.record(
                    &mut encoder,
                    4,
                    requests,
                    1,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                self.record(
                    &mut encoder,
                    5,
                    1,
                    1,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                self.record(
                    &mut encoder,
                    6,
                    (guard.buffers["rt_term_slot"].size() / 4) as u32,
                    1,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                passes_core::flush_deferred_compute(&mut encoder);
                self.queue.submit(Some(encoder.finish()));
                let status = store.read(&self.buffers["mr_state"], 32)?;
                if status[0] != 3 {
                    return Ok(status);
                }
                let mut demand = vec![0; counts::WORDS];
                demand[counts::OVERFLOW] = status[11];
                demand[counts::DEMAND + super::A_TERMS] = status[12];
                demand[counts::DEMAND + super::A_TERM_ARGS] = status[13];
                let next = grown_capacity(&guard.capacity, &demand);
                if next == guard.capacity {
                    bail!("method route interning overflowed without a growth request");
                }
                store.grow(&mut guard, next)?;
            }
        })();
        if result.is_err() {
            self.queue.write_buffer(
                &guard.buffers["rt_counts"],
                (counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.queue.submit(None);
        }
        result
    }
    fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        kernel: usize,
        lanes: u32,
        parity: usize,
        store: &Store,
        view: &RetainedTraitView<'_>,
        sub: &Publication<'_>,
        metadata: &wgpu::Buffer,
        instances: &wgpu::Buffer,
    ) -> Result<()> {
        let pass = &self.passes[kernel];
        let names = reflected_names(pass);
        let mut entries = Vec::new();
        for name in &names {
            let binding = match name.as_str() {
                "mr_routes" => view.routes.binding(),
                "mr_catalog" => view.catalog.binding(),
                "mr_proof" => view.proof.binding(),
                "mr_instances" => instances.as_entire_binding(),
                "mr_requests" => metadata.as_entire_binding(),
                "mr_config" => self.configs[parity].as_entire_binding(),
                "sb_results" => sub.results.as_entire_binding(),
                "sb_counts" => sub.counts.as_entire_binding(),
                n => self
                    .buffers
                    .get(n)
                    .or_else(|| store.buffers.get(n))
                    .ok_or_else(|| anyhow!("method routes missing buffer {n}"))?
                    .as_entire_binding(),
            };
            entries.push((name.as_str(), binding));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )?;
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("retained method routes"),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind, &[]);
        passes_core::record_compute_dispatch();
        let groups = if kernel == 5 {
            1
        } else {
            lanes.div_ceil(256).max(1)
        };
        compute.dispatch_workgroups(groups.min(65535), groups.div_ceil(65535), 1);
        Ok(())
    }
}
