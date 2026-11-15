//! Parallel schema instantiation. A closed nominal is its own binding
//! context. Each frontier contains the terms appended since the previous
//! substitution; one request per schema record realizes its field type.
use super::*;

const KEYS: [&str; 4] = [
    "type_checker/retention/projection/schema/00_plan",
    "type_checker/retention/projection/schema/01_scan",
    "type_checker/retention/projection/schema/02_requests",
    "type_checker/retention/projection/schema/03_consume",
];

#[derive(Clone, Debug, Default)]
pub struct SchemaReport {
    pub rounds: u32,
    pub requests: u32,
    pub dispatches: u32,
    pub substitution_dispatches: u32,
    pub readbacks: u32,
}

pub(super) struct SchemaProjection {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    configs: Vec<wgpu::Buffer>,
    cursor: usize,
    readback: wgpu::Buffer,
    engine: RetainedSubstitution,
    requests: SubstitutionRequests,
}

impl SchemaProjection {
    pub fn new_with_device(gpu: &crate::gpu::device::GpuDevice, capacity: SubstitutionCapacity) -> Result<Self> {
        let mut buffers = BTreeMap::new();
        for (name, bytes) in [
            ("ps_status", 16),
            ("pj_schema_ranges", 8),
            ("pj_schema_fields", 8),
        ] {
            buffers.insert(name, storage(&gpu.device, name, bytes, false));
        }
        Ok(Self {
            device: gpu.device.clone(),
            queue: gpu.queue.clone(),
            passes: KEYS
                .iter()
                .map(|key| make_pass_data_from_shader_key(&gpu.device, key, "main", key))
                .collect::<Result<_>>()?,
            buffers,
            configs: Vec::new(),
            cursor: 0,
            readback: gpu.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("retained_schema.status"),
                size: 16,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            }),
            engine: RetainedSubstitution::new_with_device(gpu, capacity)?,
            requests: SubstitutionRequests::new_with_device(&gpu.device, 1),
        })
    }

    pub fn binding(&self, name: &str) -> Option<&wgpu::Buffer> {
        self.buffers.get(name)
    }

    fn ensure(&mut self, name: &'static str, bytes: u64, preserve: bool) -> Result<()> {
        if self.buffers.get(name).is_some_and(|b| b.size() >= bytes) {
            return Ok(());
        }
        let size = bytes
            .max(16)
            .checked_next_power_of_two()
            .ok_or_else(|| anyhow!("schema capacity overflow"))?;
        if size > u64::from(self.device.limits().max_storage_buffer_binding_size) {
            bail!("schema table {name} requires {size} bytes, beyond device binding limit");
        }
        let next = storage(&self.device, name, size, false);
        if preserve && let Some(previous) = self.buffers.get(name) {
            let mut encoder = self.device.create_command_encoder(&Default::default());
            encoder.copy_buffer_to_buffer(previous, 0, &next, 0, previous.size());
            self.queue.submit(Some(encoder.finish()));
        }
        self.buffers.insert(name, next);
        Ok(())
    }

    fn dispatch(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        kernel: usize,
        config: [u32; 8],
        lanes: u32,
        extra: &[(&str, &wgpu::Buffer)],
        report: &mut SchemaReport,
    ) -> Result<()> {
        if self.cursor == self.configs.len() {
            self.configs
                .push(storage(&self.device, "ps_config", 32, false));
        }
        let cfg = &self.configs[self.cursor];
        self.cursor += 1;
        self.queue.write_buffer(cfg, 0, &words_bytes(&config));
        let pass = &self.passes[kernel];
        let names = reflected_names(pass);
        let mut bindings = Vec::new();
        for name in &names {
            let n = name.as_str();
            let b = if n == "ps_config" { Some(cfg) } else { None }
                .or_else(|| self.buffers.get(n))
                .or_else(|| extra.iter().find(|(k, _)| *k == n).map(|(_, b)| *b))
                .or_else(|| store.buffers.get(n))
                .ok_or_else(|| anyhow!("{} binds unknown {n}", pass.shader_id))?;
            bindings.push((n, b.as_entire_binding()));
        }
        let group = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &bindings,
        )?;
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("retained_schema"),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &group, &[]);
        let groups = lanes.div_ceil(256).max(1);
        compute.dispatch_workgroups(groups.min(65535), groups.div_ceil(65535), 1);
        passes_core::record_compute_dispatch();
        drop(compute);
        crate::gpu::timer::stamp_active_operation(encoder, &pass.shader_id);
        report.dispatches += 1;
        Ok(())
    }

    fn read_status(&self, report: &mut SchemaReport) -> Result<Vec<u32>> {
        report.readbacks += 1;
        let mut encoder = self.device.create_command_encoder(&Default::default());
        encoder.copy_buffer_to_buffer(&self.buffers["ps_status"], 0, &self.readback, 0, 16);
        self.queue.submit(Some(encoder.finish()));
        let slice = self.readback.slice(..);
        map_readback_blocking(&self.device, &slice, "retained_schema.status")?;
        let words = slice
            .get_mapped_range()
            .chunks_exact(4)
            .map(|w| u32::from_le_bytes(w.try_into().unwrap()))
            .collect();
        self.readback.unmap();
        Ok(words)
    }

    pub fn run(&mut self, store: &ProgramRetention) -> Result<SchemaReport> {
        let result = self.run_inner(store);
        if result.is_err() {
            let guard = store.store.lock().unwrap();
                self.queue.write_buffer(
                &guard.buffers["rt_counts"],
                (super::super::counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.queue.submit(None);
        }
        result
    }

    fn run_inner(&mut self, store: &ProgramRetention) -> Result<SchemaReport> {
        let mut report = SchemaReport::default();
        let mut lo = 32;
        let mut hi = store.status()?[A_TERMS];
        report.readbacks += 1;
        let mut base = 0u32;
        let mut encoder = self.device.create_command_encoder(&Default::default());
        encoder.clear_buffer(&self.buffers["pj_schema_ranges"], 0, None);
        self.queue.submit(Some(encoder.finish()));
        while lo < hi {
            let n = hi - lo;
            self.ensure("pj_schema_ranges", u64::from(hi) * 8, true)?;
            self.ensure("ps_scan_a", (u64::from(n) + 1) * 4, false)?;
            self.ensure("ps_scan_b", (u64::from(n) + 1) * 4, false)?;
            self.cursor = 0;
            let mut config = [lo, hi, base, 0, 0, 0, store.generation(), 0];
            let guard = store.store.lock().unwrap();
            let mut encoder = self.device.create_command_encoder(&Default::default());
            self.dispatch(&mut encoder, &guard, 0, config, n + 1, &[], &mut report)?;
            let mut distance = 1;
            loop {
                config[3] = distance;
                self.dispatch(&mut encoder, &guard, 1, config, n + 1, &[], &mut report)?;
                config[4] ^= 1;
                if distance > n / 2 {
                    break;
                }
                distance *= 2;
            }
            self.queue.submit(Some(encoder.finish()));
            drop(guard);
            let status = self.read_status(&mut report)?;
            if status[2] != 0 {
                bail!("schema planning failed: {}", status[2]);
            }
            let count = status[0];
            if count == 0 {
                break;
            }
            let end = base
                .checked_add(count)
                .ok_or_else(|| anyhow!("schema record count overflow"))?;
            self.ensure("pj_schema_fields", u64::from(end) * 8, true)?;
            if self.requests.capacity() < count {
                self.requests = SubstitutionRequests::new_with_device(&self.device, count);
            }
            let requests = self.requests.buffers().map(|(n, b)| (n, b.clone()));
            let extra = requests.iter().map(|(n, b)| (*n, b)).collect::<Vec<_>>();
            let guard = store.store.lock().unwrap();
            let mut encoder = self.device.create_command_encoder(&Default::default());
            self.dispatch(&mut encoder, &guard, 2, config, count, &extra, &mut report)?;
            self.queue.submit(Some(encoder.finish()));
            drop(guard);
            let substitution = match self.engine.run(store, &self.requests)? {
                SubstitutionRun::Published(r) => r,
                SubstitutionRun::RequestCapacity {
                    requested,
                    capacity,
                } => bail!("schema wrote {requested} requests into {capacity} rows"),
            };
            report.substitution_dispatches += substitution.dispatches;
            config[5] = substitution.publication.run;
            let published = self
                .engine
                .publication(store)
                .ok_or_else(|| anyhow!("schema publication not current"))?;
            let results = published.results.clone();
            let counts = published.counts.clone();
            let guard = store.store.lock().unwrap();
            let mut encoder = self.device.create_command_encoder(&Default::default());
            self.dispatch(
                &mut encoder,
                &guard,
                3,
                config,
                count,
                &[("sb_results", &results), ("sb_counts", &counts)],
                &mut report,
            )?;
            self.queue.submit(Some(encoder.finish()));
            drop(guard);
            let status = self.read_status(&mut report)?;
            report.rounds += 1;
            report.requests += count;
            base = end;
            lo = hi;
            hi = status[1];
        }
        Ok(report)
    }
}
