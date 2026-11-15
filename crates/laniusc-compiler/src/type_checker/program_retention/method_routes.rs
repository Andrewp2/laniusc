//! Solver proof bindings become closed method environments on the GPU.
use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail, ensure};

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

/// Fixed-point rounds of each loop in the first batch, and the bound over
/// all batches (proof depth is at most 64).
const FIRST_ROUNDS: u32 = 8;
const ROUND_BOUND: u32 = 65;
/// Config buffers: one per round modulo 6 (parity and the flag rotation),
/// the begin config and the final config.
const ROUND_CONFIGS: usize = 6;
const BEGIN_CONFIG: usize = 6;
const FINAL_CONFIG: usize = 7;
const CONFIG_WORDS: usize = 12;
/// mr_state word set while more rounds are needed (common.slang MR_PENDING).
const MR_PENDING: usize = 28;

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
    pub fn state(&self) -> &wgpu::Buffer {
        &self.buffers["mr_state"]
    }
    /// Runs the routes. Every batch also records `then(encoder, store,
    /// mr_state, mr_out)` after the routes,
    /// and its one readback returns the 32 state words followed by the
    /// leading words of each `also` buffer. Passes recorded by `then` must
    /// do nothing unless `mr_state` is finished (word 0 is 2 and
    /// `MR_PENDING` is clear).
    #[allow(clippy::too_many_arguments)]
    pub fn run(
        &mut self,
        store: &ProgramRetention,
        source: &RetainedTraitPublication,
        closed: &ClosedTraitPublication,
        sub: &Publication<'_>,
        metadata: &wgpu::Buffer,
        instances: &wgpu::Buffer,
        then: &mut dyn FnMut(&mut wgpu::CommandEncoder, &Store, &wgpu::Buffer, &wgpu::Buffer) -> Result<()>,
        also: &[(&wgpu::Buffer, usize)],
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
            for _ in 0..=FINAL_CONFIG {
                self.configs
                    .push(storage(&self.device, "mr_config", CONFIG_WORDS as u64 * 4, false));
            }
        }
        let id = view.identity;
        let config = |parity: u32, round: u32, last: bool| -> [u32; CONFIG_WORDS] {
            [
                sub.id.run,
                sub.id.generation,
                requests,
                nodes,
                parity,
                id.epoch as u32,
                (id.epoch >> 32) as u32,
                id.arena_id as u32,
                (id.arena_id >> 32) as u32,
                id.serial,
                round,
                u32::from(last),
            ]
        };
        for c in 0..ROUND_CONFIGS {
            let words = config(c as u32 % 2, c as u32 % 3, false);
            self.queue
                .write_buffer(&self.configs[c], 0, &words_bytes(&words));
        }
        // Selection marks before round 0, whose predecessor flag is round 2's.
        self.queue.write_buffer(
            &self.configs[BEGIN_CONFIG],
            0,
            &words_bytes(&config(0, 2, false)),
        );
        let mut guard = store.store.lock().unwrap();
        let result = (|| {
            loop {
                let mut encoder = self.device.create_command_encoder(&Default::default());
                self.record(
                    &mut encoder,
                    0,
                    requests.max(nodes).max(1),
                    BEGIN_CONFIG,
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
                    BEGIN_CONFIG,
                    &guard,
                    &view,
                    sub,
                    metadata,
                    instances,
                )?;
                // Reachability marking, then bottom-up evaluation. Each loop
                // stops changing at its fixed point, and the environment
                // pass runs once both have. A batch that ends before then
                // reports MR_PENDING and the next batch continues the rounds.
                let mut recorded = 0;
                let mut rounds = FIRST_ROUNDS;
                let status = loop {
                    for round in recorded..recorded + rounds {
                        self.record(
                            &mut encoder,
                            2,
                            nodes,
                            round as usize % ROUND_CONFIGS,
                            &guard,
                            &view,
                            sub,
                            metadata,
                            instances,
                        )?;
                    }
                    for round in recorded..recorded + rounds {
                        self.record(
                            &mut encoder,
                            3,
                            nodes,
                            round as usize % ROUND_CONFIGS,
                            &guard,
                            &view,
                            sub,
                            metadata,
                            instances,
                        )?;
                    }
                    recorded += rounds;
                    let last = config(1, (recorded - 1) % 3, recorded >= ROUND_BOUND);
                    self.queue.write_buffer(
                        &self.configs[FINAL_CONFIG],
                        0,
                        &words_bytes(&last),
                    );
                    self.record(
                        &mut encoder,
                        4,
                        requests,
                        FINAL_CONFIG,
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
                        FINAL_CONFIG,
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
                        FINAL_CONFIG,
                        &guard,
                        &view,
                        sub,
                        metadata,
                        instances,
                    )?;
                    passes_core::flush_deferred_compute(&mut encoder);
                    then(&mut encoder, &guard, &self.buffers["mr_state"], &self.buffers["mr_out"])?;
                    passes_core::flush_deferred_compute(&mut encoder);
                    self.queue.submit(Some(encoder.finish()));
                    let mut parts = vec![(&self.buffers["mr_state"], 32)];
                    parts.extend_from_slice(also);
                    let status = super::substitution::read_many_labeled(
                        &self.device,
                        &self.queue,
                        &parts,
                        "method_routes.state",
                    )?;
                    if status[MR_PENDING] == 0 {
                        break status;
                    }
                    ensure!(recorded < ROUND_BOUND, "method routes pending after the round bound");
                    rounds = (rounds * 2).min(ROUND_BOUND - recorded);
                    encoder = self.device.create_command_encoder(&Default::default());
                };
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
        config: usize,
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
                "mr_config" => self.configs[config].as_entire_binding(),
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
