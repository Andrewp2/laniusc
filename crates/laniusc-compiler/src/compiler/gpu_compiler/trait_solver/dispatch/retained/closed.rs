//! Hard obligations for concrete discovery instances, filled entirely on the
//! GPU against the already admitted catalog. No lexical assumptions enter.
use crate::gpu::copies::CountedCommands;
use super::*;

/// Receipt words after the route header: a deferred solve's wave state and
/// its batch receipt row.
const SOLVER_WORDS: usize = wave::READ_WORDS as usize + 8;
use super::super::kernels::wave;

/// cw_config words: the host's bound of each batch table count (+ table),
/// which 07_totals checks.
const CW_BOUNDS: usize = 104;
const CW_CONFIG_WORDS: usize = CW_BOUNDS + TABLE_COUNT;
/// cw_state words from 07_totals (closed/common.slang): the batch table
/// counts (+ table), then obligations, atoms, calls and the fault word.
const CW_COUNTS: u64 = 32;
const CW_PUBLISH: u64 = 50;
const CW_STATE_WORDS: u32 = 64;
/// Route header words the GPU copies from CW_PUBLISH: obligations and
/// atoms, then calls and the producer fault (route_abi.slang).
const RP_H_OBLIGATIONS: u64 = 12;
const RP_H_CALLS: u64 = 30;
const RP_H_PRODUCER: usize = 31;

const CLOSED_KEYS: [&str; 12] = [
    "type_checker/trait_solver/retained/closed/00_init",
    "type_checker/trait_solver/retained/closed/01_catalog",
    "type_checker/trait_solver/retained/closed/02_roots",
    "type_checker/trait_solver/retained/closed/03_wave",
    "type_checker/trait_solver/retained/closed/04_constants",
    "type_checker/trait_solver/retained/closed/05_count",
    "type_checker/trait_solver/retained/closed/06_scan",
    "type_checker/trait_solver/retained/closed/07_totals",
    "type_checker/trait_solver/retained/closed/08_fill",
    "type_checker/trait_solver/retained/entries/07_publish_routes",
    "type_checker/trait_solver/retained/entries/08_publish_finish",
    "type_checker/trait_solver/retained/closed/09_plan",
];
/// The plan pass of a chained closed solve (09_plan.slang).
const PLAN_PASS: usize = 11;
/// cw_config words of 09_plan: the obligation bound of the publication
/// pass, the catalog pass's lanes and the cw_wave word counting the solves
/// that ran.
const CW_CFG_OBLIGATIONS: usize = 20;
const CW_CFG_CATALOG_LANES: usize = 21;
const CW_CFG_RAN_WORD: usize = 22;
/// 09_plan's workgroup triples (cw_indirect), one per producer dispatch in
/// recording order: passes 0 to 5, the three scan steps, 7, 8 (the fill),
/// 9 and 10 (the publication).
const CW_ARG_SLOTS: u32 = 13;
const CW_ARG_FILL: u32 = 10;
const CW_ARG_PUBLISH: u32 = 11;
const CW_ARG_FINISH: u32 = 12;

/// What a chained closed solve takes from the GPU and the bounds that size
/// it (`RetainedTraitPublication::record_chained`).
pub struct ClosedChainInputs<'a> {
    /// Discovery's wave words: the frontier (0, 1) and the instances with
    /// closed predicates before it (3), which 09_plan advances.
    pub wave: &'a wgpu::Buffer,
    /// Discovery's status words.
    pub discovery: &'a wgpu::Buffer,
    /// The wave word 09_plan increments when the solve runs.
    pub ran_word: u32,
    /// Bound of a wave's instances with closed predicates.
    pub selected: u32,
    /// Bound of the frontier end (discovery's instance capacity).
    pub instances: u32,
    /// The store's term capacity.
    pub terms: u32,
}

#[derive(Debug)]
pub struct ClosedTraitCheck {
    pub producer_failures: u32,
    pub first_failure: u32,
    pub rows: [u32; TABLE_COUNT],
    pub batch_status: Option<[u32; 8]>,
}

/// A closed wave's packet and proofs. The source publication still owns the
/// catalog; `view` requires it and checks its identity before exposing ranges.
pub struct ClosedTraitPublication {
    packet: GpuPacket,
    routes: Arena,
    identity: RetainedTraitIdentity,
    proof_nodes: u32,
    /// Status words of the finished publication, from its receipt.
    status: [u32; 3],
    /// False until the receipt words have been read.
    received: bool,
    /// A deferred solve's wave state and batch receipt location: the
    /// receipt copy carries them, and `accept_receipt` checks the solve
    /// finished in its first submit.
    solver: Option<(LaniusBuffer<u32>, wgpu::Buffer, u64)>,
}
impl ClosedTraitPublication {
    pub fn proof_node_count(&self) -> u32 { self.proof_nodes }

    /// An upper bound of `proof_node_count` known before the receipt is
    /// read: node rows are 8 words of the proof arena.
    pub fn proof_node_bound(&self) -> u32 { self.packet.proof.logical_words / 8 }

    /// Words of the publication receipt: the header of the route arena,
    /// then a deferred solve's wave state and batch receipt.
    pub const RECEIPT_WORDS: usize = RP_HEADER_WORDS as usize + SOLVER_WORDS;

    /// Records a copy of the receipt into `target` at byte `offset`, for a
    /// caller that reads it with a later readback.
    pub fn copy_receipt(&self, encoder: &mut wgpu::CommandEncoder, target: &wgpu::Buffer, offset: u64) {
        encoder.copy_buffer_counted(
            &self.routes.buffer.buffer,
            self.routes.buffer.byte_offset,
            target,
            offset,
            u64::from(RP_HEADER_WORDS) * 4,
        );
        if let Some((state, batch, at)) = &self.solver {
            let after = offset + u64::from(RP_HEADER_WORDS) * 4;
            encoder.copy_buffer_counted(
                &state.buffer,
                state.byte_offset,
                target,
                after,
                u64::from(wave::READ_WORDS) * 4,
            );
            encoder.copy_buffer_counted(batch, *at, target, after + u64::from(wave::READ_WORDS) * 4, 32);
        }
    }

    /// Accepts the receipt words of a publication made with a deferred
    /// receipt. They are read after the publication finished on the GPU.
    /// Returns the publication's status words, or None when its deferred
    /// solve did not finish in its first submit: the publication is then
    /// incomplete and the caller solves again eagerly.
    pub fn accept_receipt(&mut self, receipt: &[u32]) -> Result<Option<[u32; 3]>> {
        ensure!(receipt.len() >= RP_HEADER_WORDS as usize, "closed publication receipt is short");
        // A deferred batch the producer could not place (07_totals): the
        // solve ran on no rows, and the eager check reports why.
        if receipt[RP_H_PRODUCER] != 0 {
            return Ok(None);
        }
        if self.solver.is_some() {
            ensure!(receipt.len() >= Self::RECEIPT_WORDS, "closed publication receipt has no solver state");
            let state = &receipt[RP_HEADER_WORDS as usize..][..wave::READ_WORDS as usize];
            super::super::wave_fault(state)?;
            if state[wave::STOP] != wave::DONE {
                return Ok(None);
            }
        }
        self.proof_nodes = receipt[24];
        self.status = [receipt[RP_H_STATUS], receipt[RP_H_STATUS + 1], receipt[RP_H_STATUS + 2]];
        self.received = true;
        Ok(Some(self.status))
    }

    /// The status words `(RP_H_STATUS..+3)`. Publication writes them last;
    /// the receipt read after it finished already holds them.
    pub fn status(&self, _source: &RetainedTraitPublication) -> Result<[u32; 3]> {
        ensure!(self.received, "closed publication receipt has not been read");
        Ok(self.status)
    }

    pub fn view<'a>(
        &'a self,
        source: &'a RetainedTraitPublication,
        store: &ProgramRetention,
    ) -> Result<RetainedTraitView<'a>> {
        let original = source.view(store)?;
        ensure!(
            original.identity.epoch == self.identity.epoch
                && original.identity.generation == self.identity.generation,
            "closed trait publication belongs to another catalog or build"
        );
        Ok(RetainedTraitView {
            identity: self.identity,
            routes: RetainedBufferRange::of(&self.routes.buffer, self.routes.logical_words),
            catalog: original.catalog,
            output: RetainedBufferRange::of(
                &self.packet.output.buffer,
                self.packet.output.logical_words,
            ),
            proof: RetainedBufferRange::of(
                &self.packet.proof.buffer,
                self.packet.proof.logical_words,
            ),
            rt_counts: original.rt_counts,
        })
    }
    #[doc(hidden)]
    pub fn query_for_test(
        &self,
        source: &RetainedTraitPublication,
        store: &ProgramRetention,
        requests: &[[u32; 3]],
    ) -> Result<Vec<[u32; 16]>> {
        query_view(
            &source.gpu,
            store,
            self.view(source, store)?,
            self.identity,
            requests,
        )
    }
}

struct ClosedProducer {
    reader: Producer,
    buffers: BTreeMap<&'static str, LaniusBuffer<u32>>,
}
impl ClosedProducer {
    fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: usize,
        lanes: u32,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        external: &[(&str, wgpu::BindingResource<'_>)],
        step: u32,
    ) -> Result<()> {
        let bind = self.bind_group(pass, store, external, step)?;
        self.dispatch(encoder, pass, lanes, &bind);
        Ok(())
    }

    fn bind_group(
        &self,
        pass: usize,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        external: &[(&str, wgpu::BindingResource<'_>)],
        step: u32,
    ) -> Result<wgpu::BindGroup> {
        let data = &self.reader.passes[pass];
        let names = reflected_names(data);
        let mut entries = Vec::new();
        for name in &names {
            let binding = if let Some((_, resource)) = external.iter().find(|(n, _)| n == name) {
                resource.clone()
            } else if name == "cw_step" {
                let b = &self.buffers["cw_step"];
                wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &b.buffer,
                    offset: b.byte_offset + u64::from(step) * STAGE_STRIDE,
                    size: std::num::NonZeroU64::new(8),
                })
            } else if matches!(name.as_str(), "cw_batch" | "cw_routes") {
                self.buffers["idle"].as_entire_binding()
            } else if let Some(b) = self.buffers.get(name.as_str()) {
                b.as_entire_binding()
            } else {
                store
                    .get(name.as_str())
                    .ok_or_else(|| anyhow!("closed trait producer missing {name}"))?
                    .as_entire_binding()
            };
            entries.push((name.as_str(), binding));
        }
        passes_core::bind_group::create_bind_group_from_bindings(
            &self.reader.device,
            Some(&data.shader_id),
            data,
            0,
            &entries,
        )
    }

    /// Records `pass` with a bind group from `bind_group` for the same pass.
    /// Records `pass` with the workgroups 09_plan wrote at `slot` of
    /// `args`.
    fn record_gated(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: usize,
        args: &LaniusBuffer<u32>,
        slot: u32,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        external: &[(&str, wgpu::BindingResource<'_>)],
        step: u32,
    ) -> Result<()> {
        let bind = self.bind_group(pass, store, external, step)?;
        passes_core::record_or_defer_compute_indirect_offset(
            encoder,
            &self.reader.passes[pass],
            &bind,
            "trait_solver.closed_instances",
            args,
            u64::from(slot) * 12,
        );
        Ok(())
    }

    fn dispatch(&self, encoder: &mut wgpu::CommandEncoder, pass: usize, lanes: u32, bind: &wgpu::BindGroup) {
        let data = &self.reader.passes[pass];
        let label = "trait_solver.closed_instances";
        let (x, y) = if matches!(pass, 3 | 7 | 10) {
            (1, 1)
        } else {
            groups(lanes)
        };
        passes_core::record_or_defer_compute_direct(encoder, data, bind, label, (x, y, 1));
    }
}

const A_TERM_ARGS: usize = 3;

/// Bounds of a deferred closed batch's table counts (07_totals checks
/// them). `selected` is the wave's instances with closed predicates: one
/// call (tables 11, 15) each, at most 32 type arguments (7, 12) and,
/// usually, at most 16 predicates (16) over the impl and its parent. Terms
/// reached from them (1, 5, 6) are bounded by the store and, usually, by 64
/// per instance. A count over its bound sends the wave to the eager check.
fn closed_bounds(selected: u32, terms: u32, term_args: u32, traits: u32) -> [u32; TABLE_COUNT] {
    let per = |n: u32| selected.saturating_mul(n);
    let reached = terms.min(per(64).saturating_add(64));
    let mut bounds = [0; TABLE_COUNT];
    bounds[1] = reached;
    bounds[5] = reached;
    bounds[6] = term_args.min(per(128).saturating_add(128));
    bounds[7] = per(32);
    bounds[12] = per(32);
    bounds[11] = selected;
    bounds[15] = selected;
    bounds[13] = selected.min(1);
    bounds[16] = per(traits.saturating_mul(2).min(16));
    bounds
}

/// A closed batch placed in its packet and route arena, from counts or
/// bounds of counts.
struct ClosedPlacement {
    packet: GpuPacket,
    submission: Submission,
    routes: Arena,
    uses: u32,
    use_map: u32,
    route_rows: u32,
    atom_ids: u32,
    route_words: u32,
}

impl RetainedTraitPublication {
    /// Places a closed batch of `rows` (exact counts or bounds) and writes
    /// its locations into `config`: the batch table offsets (68 + table),
    /// the atom identities (10) and the use map (11) of the route arena.
    fn place_closed(&self, rows: [u32; TABLE_COUNT], uses: u32, config: &mut [u32]) -> Result<ClosedPlacement> {
        let catalog = &self.gpu.catalog;
        let mut packet = self.gpu.role_packet()?;
        let (submission, offsets) = packet.packet.prepare_retained_submission(rows)?;
        config[68..86].copy_from_slice(&offsets);
        let atoms = add(catalog.slices[1].count, rows[1], "closed atoms")?;
        let use_map = RP_HEADER_WORDS;
        let route_rows = add(use_map, mul(uses, RP_USE_WORDS, "closed use map")?, "closed routes")?;
        let atom_ids = add(route_rows, mul(rows[16], RP_ROUTE_WORDS, "closed route rows")?, "closed ids")?;
        let route_words = add(atom_ids, mul(atoms, 2, "closed ids")?, "closed route arena")?;
        let routes = Arena::uninitialized(&self.gpu.workspace, "closed.routes", route_words)?;
        config[10] = atom_ids;
        config[11] = use_map;
        Ok(ClosedPlacement { packet, submission, routes, uses, use_map, route_rows, atom_ids, route_words })
    }

    /// `instances` has the discovery/projection layout: two uint4 per row,
    /// beginning with (declaration, normalized closed ENV, generation, ...).
    /// The producer solves applicable predicates for [first, end), without
    /// assumptions. Rows without predicates do not need solver calls.
    pub fn solve_instances(
        &mut self,
        store: &ProgramRetention,
        instances: &LaniusBuffer<u32>,
        first: u32,
        end: u32,
    ) -> Result<(ClosedTraitCheck, Option<ClosedTraitPublication>)> {
        self.solve_instances_with_counts(store, instances, first, end, None, false, None)
    }

    /// `solve_instances` with the store's current `rt_counts` words, when
    /// the caller has already read them after its last store write. None
    /// reads them here. With `defer_receipt` the publication is submitted
    /// but its receipt is not read: the caller copies it with
    /// `copy_receipt`, reads it with its next readback and passes it to
    /// `accept_receipt` before using the publication.
    ///
    /// `defer_solve` is the number of instances in [first, end) with closed
    /// predicates, for a solve whose progress the receipt carries. Such a
    /// check reads nothing back: the host sizes the batch from bounds
    /// derived from that number (`closed_bounds`), and the GPU writes the
    /// counts into the batch and route headers. Counts beyond the bounds,
    /// a producer failure or a wave without calls leave the batch empty and
    /// set the receipt's producer word: `accept_receipt` then returns None
    /// and the caller checks again eagerly, which reports any failure.
    pub fn solve_instances_with_counts(
        &mut self,
        store: &ProgramRetention,
        instances: &LaniusBuffer<u32>,
        first: u32,
        end: u32,
        store_counts: Option<&[u32]>,
        defer_receipt: bool,
        defer_solve: Option<u32>,
    ) -> Result<(ClosedTraitCheck, Option<ClosedTraitPublication>)> {
        ensure!(defer_receipt || defer_solve.is_none(), "a deferred closed solve needs a deferred receipt");
        self.view(store)?;
        ensure!(
            store_counts.is_none_or(|c| c.len() >= counts::WORDS),
            "closed producer store counts are short"
        );
        ensure!(
            first <= end && u64::from(end) * 32 <= instances.byte_size as u64,
            "closed instance range exceeds buffer"
        );
        store.with_store_buffers(|buffers, generation| {
            self.solve_closed(buffers, generation, instances, first, end, store_counts, defer_receipt, defer_solve)
        })
    }

    #[doc(hidden)]
    pub fn solve_instances_for_test(
        &mut self,
        store: &ProgramRetention,
        rows: &[[u32; 8]],
    ) -> Result<(ClosedTraitCheck, Option<ClosedTraitPublication>)> {
        let words: Vec<u32> = rows.iter().flatten().copied().collect();
        let usage = wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST;
        let input = self.gpu.workspace.initialized(
            "closed.test_instances",
            words.len().max(8) as u32,
            usage,
            Some(&words),
        )?;
        self.solve_instances(store, &input, 0, rows.len() as u32)
    }

    fn solve_closed(
        &mut self,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        generation: u32,
        instances: &LaniusBuffer<u32>,
        first: u32,
        end: u32,
        store_counts: Option<&[u32]>,
        defer_receipt: bool,
        defer_solve: Option<u32>,
    ) -> Result<(ClosedTraitCheck, Option<ClosedTraitPublication>)> {
        let workspace = self.gpu.workspace.clone();
        let device = self.gpu.device.clone();
        let queue = self.gpu.queue.clone();
        let usage = wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST;
        let mut producer = ClosedProducer {
            reader: Producer {
                device: device.clone(),
                queue: queue.clone(),
                readback: PagedReadback::new(&device, "closed trait counters", 4096),
                readback_bytes: 0,
                passes: CLOSED_KEYS
                    .iter()
                    .map(|key| make_pass_data_from_shader_key(&device, key, "main", key))
                    .collect::<Result<_>>()?,
            },
            buffers: BTreeMap::new(),
        };
        let status = match store_counts {
            Some(words) => words[..counts::WORDS].to_vec(),
            None => {
                let staging = workspace.initialized(
                    "closed.store_counts",
                    counts::WORDS as u32,
                    usage,
                    None,
                )?;
                let mut encoder = device.create_command_encoder(&Default::default());
                encoder.copy_buffer_counted(
                    &store["rt_counts"],
                    0,
                    &staging.buffer,
                    staging.byte_offset,
                    counts::WORDS as u64 * 4,
                );
                queue.submit(Some(encoder.finish()));
                producer
                    .reader
                    .read(&staging, counts::WORDS, "closed store counters")?
            }
        };
        let terms = status[A_TERMS];
        let lanes = add(terms, end - first, "closed producer lanes")?;
        let catalog = self.gpu.catalog.clone();
        let slots = add(terms, catalog.slices[1].count, "closed atom slots")?
            .checked_mul(2)
            .and_then(|n| n.max(1).checked_next_power_of_two())
            .ok_or_else(|| anyhow!("closed atom slots overflow"))?;
        // The count scan is a block scan: block-local scans, one workgroup
        // over the block totals, then the block prefixes added (07_scan
        // modes 0, 1, 2). The result is in cw_scan_a (config word 7 = 0).
        let steps = [0u32, 1, 2];
        let mut config = vec![0; CW_CONFIG_WORDS];
        config[..8].copy_from_slice(&[
            terms,
            status[A_PARAMS],
            status[A_DECLS],
            first,
            end,
            generation,
            slots,
            0,
        ]);
        for t in 0..TABLE_COUNT {
            config[32 + t] = catalog.slices[t].offset;
            config[50 + t] = catalog.slices[t].count;
            config[86 + t] = WIDTHS[t];
        }
        // A deferred check places its batch from bounds before the producer
        // runs; an eager one from the counts it reads after.
        let bounds = defer_solve.map(|selected| {
            closed_bounds(selected.min(end - first), terms, status[A_TERM_ARGS], status[A_TRAITS])
        });
        config[CW_BOUNDS..].copy_from_slice(&bounds.unwrap_or([u32::MAX; TABLE_COUNT]));
        let placed = match bounds {
            Some(rows) => Some(self.place_closed(rows, end, &mut config)?),
            None => None,
        };
        let mut step_words = vec![0; steps.len().max(1) * STAGE_STRIDE as usize / 4];
        for (i, mode) in steps.iter().enumerate() {
            step_words[i * 64] = *mode;
        }
        for (name, size) in [
            ("cw_config", CW_CONFIG_WORDS as u32),
            ("cw_state", CW_STATE_WORDS),
            ("cw_decl", mul(status[A_DECLS], 4, "closed declarations")?),
            ("cw_param", status[A_PARAMS]),
            ("cw_atom_slots", slots),
            // Term-sized buffers grow by powers of two (see `pow2`).
            ("cw_reach", pow2(terms)),
            ("cw_front", pow2(terms)),
            ("cw_scan_a", pow2(mul(lanes, 8, "closed scan")?)),
            ("cw_scan_b", pow2(mul(lanes, 8, "closed scan")?)),
            ("cw_blocks", pow2(mul(lanes.div_ceil(256), 8, "closed scan blocks")?)),
            ("cw_step", step_words.len() as u32),
            ("idle", 4),
        ] {
            let initial = match name {
                "cw_config" => Some(config.as_slice()),
                "cw_step" => Some(step_words.as_slice()),
                _ => None,
            };
            let use_flags = usage;
            let b = workspace.initialized(
                &format!("closed.{name}"),
                size.max(1),
                use_flags,
                initial,
            )?;
            producer.buffers.insert(name, b);
        }
        let ext = [
            ("cw_instances", instances.as_entire_binding()),
            ("cw_source_routes", self.routes.buffer.as_entire_binding()),
            ("cw_catalog", self.gpu.storage.buffer.as_entire_binding()),
        ];
        let mut encoder = device.create_command_encoder(&Default::default());
        // One compute pass per submit, flushed before the submit.
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.closed_instances",
        );
        producer.record(
            &mut encoder,
            0,
            slots
                .max(terms)
                .max(status[A_DECLS])
                .max(status[A_PARAMS])
                .max(CW_STATE_WORDS),
            store,
            &ext,
            0,
        )?;
        producer.record(
            &mut encoder,
            1,
            catalog.slices[1]
                .count
                .max(catalog.slices[2].count)
                .max(catalog.slices[4].count),
            store,
            &ext,
            0,
        )?;
        producer.record(&mut encoder, 2, end - first, store, &ext, 0)?;
        // One workgroup expands the term closure level by level (03_wave).
        // Retained type height is bounded by 64, so its 65 levels consume
        // any valid frontier; the count pass reports a frontier still
        // pending in cw_state[5], which is a producer failure (code 7).
        producer.record(&mut encoder, 3, 1, store, &ext, 0)?;
        producer.record(&mut encoder, 4, terms, store, &ext, 0)?;
        producer.record(&mut encoder, 5, lanes, store, &ext, 0)?;
        for (i, mode) in steps.iter().enumerate() {
            let scan_lanes = if *mode == 1 { 1 } else { lanes };
            producer.record(&mut encoder, 6, scan_lanes, store, &ext, i as u32)?;
        }
        producer.record(&mut encoder, 7, 1, store, &ext, 0)?;
        passes_core::flush_deferred_compute(&mut encoder);
        drop(batch);
        queue.submit(Some(encoder.finish()));
        let mut report = ClosedTraitCheck {
            producer_failures: 0,
            first_failure: u32::MAX,
            rows: [0; TABLE_COUNT],
            batch_status: None,
        };
        let placed = match placed {
            Some(placed) => placed,
            None => {
                let mut state = producer
                    .reader
                    .read(&producer.buffers["cw_state"], 32, "closed trait demand")?;
                if state[5] != 0 {
                    state[0] |= 1 << 7;
                    state[1] = 0;
                }
                report.producer_failures = state[0];
                report.first_failure = state[1];
                if state[0] != 0 {
                    return Ok((report, None));
                }
                for (c, t) in [
                    (0, 1),
                    (1, 5),
                    (2, 6),
                    (3, 7),
                    (3, 12),
                    (4, 11),
                    (4, 15),
                    (5, 16),
                ] {
                    report.rows[t] = state[8 + c];
                }
                report.rows[13] = u32::from(report.rows[15] != 0);
                if report.rows[15] == 0 {
                    return Ok((report, None));
                }
                let placed = self.place_closed(report.rows, end, &mut config)?;
                producer.buffers["cw_config"].write(&queue, 0, &words_bytes(&config));
                placed
            }
        };
        let ClosedPlacement { mut packet, submission, routes, uses, atom_ids, use_map, route_rows, route_words } = placed;
        let gpu_counts = defer_solve.map(|_| (&producer.buffers["cw_state"], CW_COUNTS));
        // Source identity words live at a count-derived offset, not read
        // from a semantic row: source layout is fixed by its packet counts.
        let source_atom_ids = self.route_words - catalog.slices[1].count * 2;
        let catalog_buffer = self.gpu.storage.buffer.clone();
        let (readback, output_layout) =
            self.gpu
                .check_retained(&mut packet, &submission, false, gpu_counts, defer_solve.is_some(), |encoder, input| {
                    routes
                        .buffer
                        .clear(encoder, 0, Some(u64::from(route_words) * 4));
                    self.routes.buffer.copy_to(
                        encoder,
                        u64::from(source_atom_ids) * 4,
                        &routes.buffer,
                        u64::from(atom_ids) * 4,
                        u64::from(catalog.slices[1].count) * 8,
                    );
                    let ext = [
                        ("cw_instances", instances.as_entire_binding()),
                        ("cw_source_routes", self.routes.buffer.as_entire_binding()),
                        ("cw_catalog", catalog_buffer.as_entire_binding()),
                        ("cw_batch", input.buffer.as_entire_binding()),
                        ("cw_routes", routes.buffer.as_entire_binding()),
                    ];
                    producer.record(encoder, 8, lanes, store, &ext, 0)
                })?;
        report.batch_status = readback.map(|r| r.batch_status);
        let solver = if defer_solve.is_some() {
            let state = self
                .gpu
                .last_wave_state
                .lock()
                .unwrap()
                .clone()
                .ok_or_else(|| anyhow!("deferred closed solve has no wave state"))?;
            let output = &packet.output.buffer;
            let at = output.byte_offset + u64::from(output_layout.slices[10].offset) * 4;
            Some((state, output.buffer.clone(), at))
        } else {
            None
        };
        let identity = RetainedTraitIdentity {
            epoch: catalog.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            generation,
        };
        let mut header = vec![0; RP_HEADER_WORDS as usize];
        header[..8].copy_from_slice(&[
            RP_MAGIC,
            1,
            identity.epoch as u32,
            (identity.epoch >> 32) as u32,
            identity.arena_id as u32,
            (identity.arena_id >> 32) as u32,
            identity.serial,
            generation,
        ]);
        header[10] = INVALID;
        header[11] = uses;
        // Obligations, atoms (12, 13), calls and the producer fault (30,
        // 31) are copied from 07_totals below.
        header[14] = use_map;
        header[15] = route_rows;
        header[16] = atom_ids;
        for (word, t) in [(17, 9), (18, 10), (27, 1), (28, 5), (29, 6)] {
            header[word] = catalog.slices[t].offset;
        }
        header[19] = catalog.slices[9].count;
        header[20] = catalog.slices[10].count;
        for (word, t) in [(32, 3), (33, 4), (34, 5), (35, 10)] {
            header[word] = output_layout.slices[t].offset;
        }
        header[36] = catalog.outputs[0].offset;
        header[37] = packet.proof.logical_words;
        header[38] = self.gpu.storage.logical_words;
        header[39] = packet.output.logical_words;
        header[40..44].copy_from_slice(&[
            status[A_DIR],
            status[A_TRAITS],
            status[counts::JOBS],
            status[A_DECLS],
        ]);
        // The verdict publish_finish requires: the solve finished (its stop
        // word, copied below). The catalog's fill and recipes were checked
        // with the source publication.
        header[RP_H_FILL_FAULTS as usize] = 0;
        header[RP_H_RECIPE_STATUS as usize] = 1;
        let mut encoder = device.create_command_encoder(&Default::default());
        routes.upload(
            &mut encoder,
            &[ArenaWrite {
                first_word: 0,
                words: header,
            }],
        )?;
        self.gpu.copy_solve_stop(&mut encoder, &routes.buffer)?;
        let state = &producer.buffers["cw_state"];
        state.copy_to(&mut encoder, CW_PUBLISH * 4, &routes.buffer, RP_H_OBLIGATIONS * 4, 8);
        state.copy_to(&mut encoder, (CW_PUBLISH + 2) * 4, &routes.buffer, RP_H_CALLS * 4, 8);
        let ext = [
            ("rc_routes", routes.buffer.as_entire_binding()),
            ("rp_catalog", self.gpu.storage.buffer.as_entire_binding()),
            ("rp_output", packet.output.buffer.as_entire_binding()),
            ("rp_proof", packet.proof.buffer.as_entire_binding()),
        ];
        // One compute pass per submit, flushed before the submit.
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.closed_instances",
        );
        producer.record(
            &mut encoder,
            9,
            add(uses, submission.obligation_span.count, "closed publication lanes")?,
            store,
            &ext,
            0,
        )?;
        producer.record(&mut encoder, 10, 1, store, &ext, 0)?;
        passes_core::flush_deferred_compute(&mut encoder);
        drop(batch);
        queue.submit(Some(encoder.finish()));
        let mut publication = ClosedTraitPublication {
            packet,
            routes,
            identity,
            proof_nodes: 0,
            status: [0; 3],
            received: false,
            solver,
        };
        // Later submissions on this queue run after the publication, so a
        // caller may read the receipt with its own next readback.
        if !defer_receipt {
            let receipt = producer.reader.read(
                &publication.routes.buffer,
                RP_HEADER_WORDS as usize,
                "closed publication receipt",
            )?;
            publication.accept_receipt(&receipt)?;
        }
        Ok((report, Some(publication)))
    }
}

impl RetainedTraitPublication {
    /// Records the closed solve of a chained discovery wave before the host
    /// has read the status of the wave before it. `status` holds the store
    /// counters of the last readback: the declarations, parameters and
    /// traits, which discovery does not change. Everything else is sized
    /// from `inputs`: the frontier end by the instance capacity, the terms
    /// by the term capacity and the batch by `closed_bounds` of
    /// `inputs.selected`. 09_plan takes the frontier, the term count and
    /// the gate from the GPU, and every later producer pass dispatches the
    /// workgroups it wrote: none when the wave has no new instances with
    /// closed predicates or discovery stopped. The solve is deferred and
    /// its receipt is not read: discovery copies it (`copy_receipt`) and
    /// checks it on the GPU (05_publish mode 4). A batch over its bounds
    /// leaves the producer word set, and the check stops the chain.
    pub fn record_chained(
        &mut self,
        encoder: Option<wgpu::CommandEncoder>,
        store: &ProgramRetention,
        instances: &LaniusBuffer<u32>,
        status: &[u32],
        inputs: &ClosedChainInputs<'_>,
    ) -> Result<(ClosedTraitPublication, Option<wgpu::CommandEncoder>)> {
        self.view(store)?;
        ensure!(status.len() >= counts::WORDS, "chained closed solve store counts are short");
        ensure!(
            u64::from(inputs.instances) * 32 <= instances.byte_size as u64,
            "chained closed instance capacity exceeds the instance buffer"
        );
        store.with_store_buffers(|buffers, generation| {
            // With an encoder the solve records into it: one submit for the
            // wave's frontier, the solve and its resolution. Without one it
            // submits as it records, so an idle GPU starts at once.
            let Some(encoder) = encoder else {
                return Ok((self.record_closed_chained(buffers, generation, instances, status, inputs)?, None));
            };
            self.gpu.park_chained(encoder);
            let recorded = self.record_closed_chained(buffers, generation, instances, status, inputs);
            let encoder = self.gpu.take_chained();
            let publication = recorded?;
            Ok((publication, Some(encoder.ok_or_else(|| anyhow!("a chained solve kept its encoder"))?)))
        })
    }

    fn record_closed_chained(
        &mut self,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        generation: u32,
        instances: &LaniusBuffer<u32>,
        status: &[u32],
        inputs: &ClosedChainInputs<'_>,
    ) -> Result<ClosedTraitPublication> {
        let workspace = self.gpu.workspace.clone();
        let device = self.gpu.device.clone();
        let queue = self.gpu.queue.clone();
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
        let producer = ClosedProducer {
            reader: Producer {
                device: device.clone(),
                queue: queue.clone(),
                readback: PagedReadback::new(&device, "closed trait counters", 4096),
                readback_bytes: 0,
                passes: CLOSED_KEYS
                    .iter()
                    .map(|key| make_pass_data_from_shader_key(&device, key, "main", key))
                    .collect::<Result<_>>()?,
            },
            buffers: BTreeMap::new(),
        };
        let catalog = self.gpu.catalog.clone();
        let terms = inputs.terms;
        let end = inputs.instances;
        let lanes = add(terms, end, "chained closed producer lanes")?;
        let slots = add(terms, catalog.slices[1].count, "closed atom slots")?
            .checked_mul(2)
            .and_then(|n| n.max(1).checked_next_power_of_two())
            .ok_or_else(|| anyhow!("closed atom slots overflow"))?;
        let steps = [0u32, 1, 2];
        let mut config = vec![0; CW_CONFIG_WORDS];
        // Words 0, 3 and 4 (terms, frontier) are 09_plan's.
        config[..8].copy_from_slice(&[terms, status[A_PARAMS], status[A_DECLS], 0, 0, generation, slots, 0]);
        for t in 0..TABLE_COUNT {
            config[32 + t] = catalog.slices[t].offset;
            config[50 + t] = catalog.slices[t].count;
            config[86 + t] = WIDTHS[t];
        }
        let bounds = closed_bounds(inputs.selected, terms, u32::MAX, status[A_TRAITS]);
        config[CW_BOUNDS..].copy_from_slice(&bounds);
        let ClosedPlacement { mut packet, submission, routes, uses, atom_ids, use_map, route_rows, route_words } =
            self.place_closed(bounds, end, &mut config)?;
        config[CW_CFG_OBLIGATIONS] = submission.obligation_span.count;
        config[CW_CFG_CATALOG_LANES] = catalog.slices[1].count.max(catalog.slices[2].count).max(catalog.slices[4].count);
        config[CW_CFG_RAN_WORD] = inputs.ran_word;
        let mut step_words = vec![0; steps.len() * STAGE_STRIDE as usize / 4];
        for (i, mode) in steps.iter().enumerate() {
            step_words[i * 64] = *mode;
        }
        let mut producer = producer;
        for (name, size) in [
            ("cw_config", CW_CONFIG_WORDS as u32),
            ("cw_state", CW_STATE_WORDS),
            ("cw_decl", mul(status[A_DECLS], 4, "closed declarations")?),
            ("cw_param", status[A_PARAMS]),
            ("cw_atom_slots", slots),
            ("cw_reach", pow2(terms)),
            ("cw_front", pow2(terms)),
            ("cw_scan_a", pow2(mul(lanes, 8, "closed scan")?)),
            ("cw_scan_b", pow2(mul(lanes, 8, "closed scan")?)),
            ("cw_blocks", pow2(mul(lanes.div_ceil(256), 8, "closed scan blocks")?)),
            ("cw_step", step_words.len() as u32),
            ("cw_indirect", CW_ARG_SLOTS * 3),
            ("idle", 4),
        ] {
            let initial = match name {
                "cw_config" => Some(config.as_slice()),
                "cw_step" => Some(step_words.as_slice()),
                _ => None,
            };
            let flags = if name == "cw_indirect" { usage | wgpu::BufferUsages::INDIRECT } else { usage };
            let b = workspace.initialized(&format!("closed.{name}"), size.max(1), flags, initial)?;
            producer.buffers.insert(name, b);
        }
        let args = producer.buffers["cw_indirect"].clone();
        let ext = [
            ("cw_instances", instances.as_entire_binding()),
            ("cw_source_routes", self.routes.buffer.as_entire_binding()),
            ("cw_catalog", self.gpu.storage.buffer.as_entire_binding()),
            ("cw_wave", inputs.wave.as_entire_binding()),
            ("cw_discovery", inputs.discovery.as_entire_binding()),
        ];
        let mut encoder = self.gpu.wave_encoder();
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.closed_instances",
        );
        producer.record(&mut encoder, PLAN_PASS, 1, store, &ext, 0)?;
        for (slot, pass) in [(0u32, 0usize), (1, 1), (2, 2), (3, 3), (4, 4), (5, 5)] {
            producer.record_gated(&mut encoder, pass, &args, slot, store, &ext, 0)?;
        }
        for (i, _) in steps.iter().enumerate() {
            producer.record_gated(&mut encoder, 6, &args, 6 + i as u32, store, &ext, i as u32)?;
        }
        producer.record_gated(&mut encoder, 7, &args, 9, store, &ext, 0)?;
        self.gpu.submit_wave(encoder);
        drop(batch);
        let gpu_counts = Some((&producer.buffers["cw_state"], CW_COUNTS));
        let source_atom_ids = self.route_words - catalog.slices[1].count * 2;
        let catalog_buffer = self.gpu.storage.buffer.clone();
        let (_, output_layout) = self.gpu.check_retained(&mut packet, &submission, false, gpu_counts, true, |encoder, input| {
            routes.buffer.clear(encoder, 0, Some(u64::from(route_words) * 4));
            self.routes.buffer.copy_to(
                encoder,
                u64::from(source_atom_ids) * 4,
                &routes.buffer,
                u64::from(atom_ids) * 4,
                u64::from(catalog.slices[1].count) * 8,
            );
            let ext = [
                ("cw_instances", instances.as_entire_binding()),
                ("cw_source_routes", self.routes.buffer.as_entire_binding()),
                ("cw_catalog", catalog_buffer.as_entire_binding()),
                ("cw_batch", input.buffer.as_entire_binding()),
                ("cw_routes", routes.buffer.as_entire_binding()),
            ];
            producer.record_gated(encoder, 8, &args, CW_ARG_FILL, store, &ext, 0)
        })?;
        let state = self
            .gpu
            .last_wave_state
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| anyhow!("chained closed solve has no wave state"))?;
        let output = &packet.output.buffer;
        let at = output.byte_offset + u64::from(output_layout.slices[10].offset) * 4;
        let solver = Some((state, output.buffer.clone(), at));
        let identity = RetainedTraitIdentity {
            epoch: catalog.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            generation,
        };
        let mut header = vec![0; RP_HEADER_WORDS as usize];
        header[..8].copy_from_slice(&[
            RP_MAGIC,
            1,
            identity.epoch as u32,
            (identity.epoch >> 32) as u32,
            identity.arena_id as u32,
            (identity.arena_id >> 32) as u32,
            identity.serial,
            generation,
        ]);
        header[10] = INVALID;
        // The use count (11), the store words 40 to 43 and the producer's
        // totals are copied on the GPU below.
        header[11] = uses;
        header[14] = use_map;
        header[15] = route_rows;
        header[16] = atom_ids;
        for (word, t) in [(17, 9), (18, 10), (27, 1), (28, 5), (29, 6)] {
            header[word] = catalog.slices[t].offset;
        }
        header[19] = catalog.slices[9].count;
        header[20] = catalog.slices[10].count;
        for (word, t) in [(32, 3), (33, 4), (34, 5), (35, 10)] {
            header[word] = output_layout.slices[t].offset;
        }
        header[36] = catalog.outputs[0].offset;
        header[37] = packet.proof.logical_words;
        header[38] = self.gpu.storage.logical_words;
        header[39] = packet.output.logical_words;
        // The verdict publish_finish requires: the solve finished (its stop
        // word, copied below). The catalog's fill and recipes were checked
        // with the source publication.
        header[RP_H_FILL_FAULTS as usize] = 0;
        header[RP_H_RECIPE_STATUS as usize] = 1;
        let mut encoder = self.gpu.wave_encoder();
        routes.upload(&mut encoder, &[ArenaWrite { first_word: 0, words: header }])?;
        self.gpu.copy_solve_stop(&mut encoder, &routes.buffer)?;
        let cw_state = &producer.buffers["cw_state"];
        cw_state.copy_to(&mut encoder, CW_PUBLISH * 4, &routes.buffer, RP_H_OBLIGATIONS * 4, 8);
        cw_state.copy_to(&mut encoder, (CW_PUBLISH + 2) * 4, &routes.buffer, RP_H_CALLS * 4, 8);
        // The frontier end 09_plan wrote is the use count.
        producer.buffers["cw_config"].copy_to(&mut encoder, 4 * 4, &routes.buffer, 11 * 4, 4);
        for (word, arena) in [(40u64, A_DIR), (41, A_TRAITS), (42, counts::JOBS), (43, A_DECLS)] {
            let target = routes.buffer.byte_offset + word * 4;
            encoder.copy_buffer_counted(&store["rt_counts"], arena as u64 * 4, &routes.buffer.buffer, target, 4);
        }
        let ext = [
            ("rc_routes", routes.buffer.as_entire_binding()),
            ("rp_catalog", self.gpu.storage.buffer.as_entire_binding()),
            ("rp_output", packet.output.buffer.as_entire_binding()),
            ("rp_proof", packet.proof.buffer.as_entire_binding()),
        ];
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.closed_instances",
        );
        producer.record_gated(&mut encoder, 9, &args, CW_ARG_PUBLISH, store, &ext, 0)?;
        producer.record_gated(&mut encoder, 10, &args, CW_ARG_FINISH, store, &ext, 0)?;
        self.gpu.submit_wave(encoder);
        drop(batch);
        Ok(ClosedTraitPublication {
            packet,
            routes,
            identity,
            proof_nodes: 0,
            status: [0; 3],
            received: false,
            solver,
        })
    }
}
