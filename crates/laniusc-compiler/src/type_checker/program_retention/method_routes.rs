//! Solver proof bindings become closed method environments on the GPU.
use crate::gpu::copies::{CountedCommands, CountedWrites};
use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail, ensure};

use super::{
    ProgramRetention,
    METHOD_ROUTES_SYNC_SLOT,
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
    gpu::{
        operations::{StepProgramOperation, step_program_group_counts, step_program_group_variant},
        passes_core::{self, PassData, make_pass_data_from_shader_key},
    },
};
const PROGRAM: &str = "type_checker/retention/method_routes/build_retained_method_routes";
const SYNC_FAILED: usize = 29;

const CONFIG_WORDS: usize = 12;
/// mr_state word that would ask for more rounds (common.slang MR_PENDING).
/// The fixed-point passes run to their bound in one dispatch, so it stays
/// clear.
pub(super) const MR_PENDING: usize = 28;

pub(super) struct MethodRoutes {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    pass: PassData,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    config: wgpu::Buffer,
}
impl MethodRoutes {
    pub fn new_with_device(gpu: &crate::gpu::device::GpuDevice) -> Result<Self> {
        let pass = make_pass_data_from_shader_key(&gpu.device, PROGRAM, "main", PROGRAM)?;
        let config = storage(&gpu.device, "mr_config", CONFIG_WORDS as u64 * 4, false);
        Ok(Self {
            device: gpu.device.clone(),
            queue: gpu.queue.clone(),
            pass,
            buffers: BTreeMap::new(),
            config,
        })
    }
    fn ensure(&mut self, name: &'static str, bytes: u64) -> Result<()> {
        let limits = self.device.limits();
        if bytes > limits.max_buffer_size
            || bytes > u64::from(limits.max_storage_buffer_binding_size)
        {
            bail!("method routes {name} exceeds device capacity");
        }
        // Powers of two: the proof node bound grows between builds, and a
        // kept buffer keeps its cached bind groups.
        if self.buffers.get(name).is_none_or(|b| b.size() < bytes) {
            let limit = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
            let rounded = bytes.max(4).next_power_of_two();
            let bytes = if rounded <= limit { rounded } else { bytes.max(4) };
            self.buffers.insert(name, storage(&self.device, name, bytes, false));
        }
        Ok(())
    }
    pub fn state(&self) -> &wgpu::Buffer {
        &self.buffers["mr_state"]
    }
    pub fn output(&self) -> &wgpu::Buffer {
        &self.buffers["mr_out"]
    }
    /// Allocates the tables for at most `requests` requests and `nodes`
    /// proof nodes, and the config buffers.
    pub fn prepare(&mut self, requests: u32, nodes: u32) -> Result<()> {
        for (name, bytes) in [
            ("mr_state", 128),
            ("mr_selected", u64::from(requests.max(1)) * 16),
            ("mr_reach", u64::from(nodes.max(1)) * 4),
            ("mr_values_a", u64::from(nodes.max(1)) * 4),
            ("mr_values_b", u64::from(nodes.max(1)) * 4),
            ("mr_args", u64::from(requests.max(1)) * 64 * 4),
            ("mr_env_slots", (u64::from(requests.max(1)) * 2).next_power_of_two() * 4),
            ("mr_out", u64::from(requests.max(1)) * 16),
        ] {
            self.ensure(name, bytes)?;
        }
        Ok(())
    }

    fn write_config(&self, words: &Config) {
        // Selection marks before level 0, whose predecessor is round 2.
        self.queue.write_buffer_counted(&self.config, 0, &words_bytes(&words.at(0, 2)));
    }

    #[allow(clippy::too_many_arguments)]
    fn record_batch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        guard: &Store,
        view: &RetainedTraitView<'_>,
        sub: (&wgpu::Buffer, &wgpu::Buffer),
        metadata: &wgpu::Buffer,
        instances: &wgpu::Buffer,
        config: &Config,
        requests: u32,
    ) -> Result<()> {
        let names = reflected_names(&self.pass);
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let binding = match name.as_str() {
                "step_program_sync" | "program_launch" => continue,
                "mr_routes" => view.routes.whole_binding(),
                "mr_catalog" => view.catalog.binding(),
                "mr_proof" => view.proof.binding(),
                "mr_instances" => instances.as_entire_binding(),
                "mr_requests" => metadata.as_entire_binding(),
                "mr_config" => self.config.as_entire_binding(),
                "sb_results" => sub.0.as_entire_binding(),
                "sb_counts" => sub.1.as_entire_binding(),
                n => self.buffers.get(n).or_else(|| guard.buffers.get(n))
                    .ok_or_else(|| anyhow!("method routes missing buffer {n}"))?
                    .as_entire_binding(),
            };
            entries.push((name.as_str(), binding));
        }
        let rows = u64::from(requests.max(config.nodes));
        let groups = step_program_group_counts()[step_program_group_variant(rows)];
        let program = StepProgramOperation::new_reflected(
            &self.device, PROGRAM, &self.pass, &entries, &guard.step_program_sync,
            METHOD_ROUTES_SYNC_SLOT, groups, 0,
        )?;
        program.record(encoder)?;
        passes_core::flush_deferred_compute(encoder);
        encoder.copy_buffer_counted(
            &guard.step_program_sync,
            StepProgramOperation::failed_offset(METHOD_ROUTES_SYNC_SLOT),
            self.state(),
            (SYNC_FAILED * 4) as u64,
            4,
        );
        Ok(())
    }

    /// Supplies the closed wave's proof tables and method workspace.
    pub(super) fn prepare_wave<'a>(
        &'a self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        view: &'a RetainedTraitView<'_>,
        run: u32,
        nodes: (&wgpu::Buffer, u64, u32),
    ) -> Vec<(&'static str, wgpu::BindingResource<'a>)> {
        let config = Config::new(run, store.generation, 0, nodes.2, view.identity);
        self.write_config(&config);
        encoder.copy_buffer_counted(nodes.0, nodes.1, &self.config, 12, 4);
        let mut bindings = vec![
            ("mr_routes", view.routes.whole_binding()),
            ("mr_catalog", view.catalog.binding()),
            ("mr_proof", view.proof.binding()),
            ("mr_config", self.config.as_entire_binding()),
        ];
        bindings.extend(self.buffers.iter().map(|(&name, buffer)| (name, buffer.as_entire_binding())));
        bindings
    }

    /// Records the first batch of a run whose request and proof node counts
    /// are still on the GPU: the 4-byte words at `requests.1` and
    /// `nodes.1` are copied into every config before the passes. Lanes and
    /// tables are sized by the bounds, and `prepare` must have covered
    /// them. Kernels that consume a substitution check that `run` is
    /// current, so a run that did not publish selects nothing.
    #[allow(clippy::too_many_arguments)]
    pub fn record_first_batch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        guard: &Store,
        view: &RetainedTraitView<'_>,
        run: u32,
        sub: (&wgpu::Buffer, &wgpu::Buffer),
        requests: (&wgpu::Buffer, u64, u32),
        nodes: (&wgpu::Buffer, u64, u32),
        metadata: &wgpu::Buffer,
        instances: &wgpu::Buffer,
    ) -> Result<()> {
        let config = Config::new(run, guard.generation, 0, nodes.2, view.identity);
        self.write_config(&config);
        encoder.copy_buffer_counted(requests.0, requests.1, &self.config, 8, 4);
        encoder.copy_buffer_counted(nodes.0, nodes.1, &self.config, 12, 4);
        self.record_batch(encoder, guard, view, sub, metadata, instances, &config, requests.2)
    }
    /// Runs the routes. Every batch also records `then(encoder, store,
    /// mr_state, mr_out)` after the routes, and its one readback returns
    /// the 32 state words followed by the leading words of each `also`
    /// buffer. Passes recorded by `then` must do nothing unless `mr_state`
    /// is finished (word 0 is 2 and `MR_PENDING` is clear).
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
        self.prepare(requests, nodes)?;
        let config = Config::new(sub.id.run, sub.id.generation, requests, nodes, view.identity);
        self.write_config(&config);
        let buffers = (sub.results, sub.counts);
        let mut guard = store.store.lock().unwrap();
        let result = (|| {
            loop {
                let mut encoder = self.device.create_command_encoder(&Default::default());
                // One compute pass per submit, flushed before `then`.
                let batch = passes_core::DeferredComputeBatchGuard::begin(
                    passes_core::compute_pass_batching_allowed(false),
                    "retained method routes",
                );
                self.record_batch(&mut encoder, &guard, &view, buffers, metadata, instances, &config, requests)?;
                passes_core::flush_deferred_compute(&mut encoder);
                then(&mut encoder, &guard, &self.buffers["mr_state"], &self.buffers["mr_out"])?;
                passes_core::flush_deferred_compute(&mut encoder);
                drop(batch);
                self.queue.submit(Some(encoder.finish()));
                let mut parts = vec![(&self.buffers["mr_state"], 32)];
                parts.extend_from_slice(also);
                let status =
                    super::substitution::read_many_labeled(&self.device, &self.queue, &parts, crate::readback_label!("method_routes.state"))?;
                ensure!(status[SYNC_FAILED] == 0, "retention program {PROGRAM} failed to synchronize");
                ensure!(status[MR_PENDING] == 0, "method routes pending after the level bound");
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
            self.queue.write_buffer_counted(
                &guard.buffers["rt_counts"],
                (counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.queue.submit(None);
        }
        result
    }
}

/// The words of one run's configs; `at` adds the value parity and the flag
/// round.
struct Config {
    run: u32,
    generation: u32,
    requests: u32,
    nodes: u32,
    identity: crate::compiler::RetainedTraitIdentity,
}
impl Config {
    fn new(run: u32, generation: u32, requests: u32, nodes: u32, identity: crate::compiler::RetainedTraitIdentity) -> Self {
        Self { run, generation, requests, nodes, identity }
    }
    fn at(&self, parity: u32, round: u32) -> [u32; CONFIG_WORDS] {
        let id = self.identity;
        [
            self.run,
            self.generation,
            self.requests,
            self.nodes,
            parity,
            id.epoch as u32,
            (id.epoch >> 32) as u32,
            id.arena_id as u32,
            (id.arena_id >> 32) as u32,
            id.serial,
            round,
            0,
        ]
    }
}
