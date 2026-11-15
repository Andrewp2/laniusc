//! Hard obligations for concrete discovery instances, filled entirely on the
//! GPU against the already admitted catalog. No lexical assumptions enter.
use super::*;

const CLOSED_KEYS: [&str; 12] = [
    "type_checker/trait_solver/retained/closed/00_init",
    "type_checker/trait_solver/retained/closed/01_catalog",
    "type_checker/trait_solver/retained/closed/02_roots",
    "type_checker/trait_solver/retained/closed/03_wave",
    "type_checker/trait_solver/retained/closed/04_expand",
    "type_checker/trait_solver/retained/closed/05_constants",
    "type_checker/trait_solver/retained/closed/06_count",
    "type_checker/trait_solver/retained/closed/07_scan",
    "type_checker/trait_solver/retained/closed/08_totals",
    "type_checker/trait_solver/retained/closed/09_fill",
    "type_checker/trait_solver/retained/entries/07_publish_routes",
    "type_checker/trait_solver/retained/entries/08_publish_finish",
];

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
}
impl ClosedTraitPublication {
    pub fn proof_node_count(&self) -> u32 { self.proof_nodes }

    pub fn status(&self, source: &RetainedTraitPublication) -> Result<[u32; 3]> {
        let region = ReadbackRegion::from_buffer(
            &self.routes.buffer,
            RP_H_STATUS as u64 * 4,
            12,
            "closed publication status",
        )?;
        let raw = source.gpu.readback.read_regions(
            &source.gpu.device,
            &source.gpu.queue,
            &[region],
            "closed publication status",
        )?;
        let words = super::super::words(&raw[0])?;
        Ok([words[0], words[1], words[2]])
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
            } else if name == "cw_indirect" && pass == 4 {
                self.buffers["idle"].as_entire_binding()
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
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.reader.device,
            Some(&data.shader_id),
            data,
            0,
            &entries,
        )?;
        let label = "trait_solver.closed_instances";
        if pass == 4 {
            let indirect = &self.buffers["cw_indirect"];
            passes_core::record_or_defer_compute_indirect(encoder, data, &bind, label, indirect);
        } else {
            let (x, y) = if matches!(pass, 3 | 8 | 11) {
                (1, 1)
            } else {
                groups(lanes)
            };
            passes_core::record_or_defer_compute_direct(encoder, data, &bind, label, (x, y, 1));
        }
        Ok(())
    }
}

impl RetainedTraitPublication {
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
        self.view(store)?;
        ensure!(
            first <= end && u64::from(end) * 32 <= instances.byte_size as u64,
            "closed instance range exceeds buffer"
        );
        store.with_store_buffers(|buffers, generation| {
            self.solve_closed(buffers, generation, instances, first, end)
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
        let staging =
            workspace.initialized("closed.store_counts", counts::WORDS as u32, usage, None)?;
        let mut encoder = device.create_command_encoder(&Default::default());
        encoder.copy_buffer_to_buffer(
            &store["rt_counts"],
            0,
            &staging.buffer,
            staging.byte_offset,
            counts::WORDS as u64 * 4,
        );
        queue.submit(Some(encoder.finish()));
        let status = producer
            .reader
            .read(&staging, counts::WORDS, "closed store counters")?;
        let terms = status[A_TERMS];
        let lanes = add(terms, end - first, "closed producer lanes")?;
        let catalog = self.gpu.catalog.clone();
        let slots = add(terms, catalog.slices[1].count, "closed atom slots")?
            .checked_mul(2)
            .and_then(|n| n.max(1).checked_next_power_of_two())
            .ok_or_else(|| anyhow!("closed atom slots overflow"))?;
        let mut steps = Vec::new();
        let mut distance = 1u32;
        while distance < lanes {
            steps.push(distance);
            distance = distance
                .checked_mul(2)
                .ok_or_else(|| anyhow!("closed scan overflow"))?;
        }
        let mut config = vec![0; 104];
        config[..8].copy_from_slice(&[
            terms,
            status[A_PARAMS],
            status[A_DECLS],
            first,
            end,
            generation,
            slots,
            steps.len() as u32 % 2,
        ]);
        for t in 0..TABLE_COUNT {
            config[32 + t] = catalog.slices[t].offset;
            config[50 + t] = catalog.slices[t].count;
            config[86 + t] = WIDTHS[t];
        }
        let mut step_words = vec![0; steps.len().max(1) * STAGE_STRIDE as usize / 4];
        for (i, distance) in steps.iter().enumerate() {
            step_words[i * 64] = *distance;
            step_words[i * 64 + 1] = i as u32 % 2;
        }
        for (name, size) in [
            ("cw_config", 104),
            ("cw_state", 32),
            ("cw_decl", mul(status[A_DECLS], 4, "closed declarations")?),
            ("cw_param", status[A_PARAMS]),
            ("cw_atom_slots", slots),
            ("cw_reach", terms),
            ("cw_front", terms),
            ("cw_indirect", 3),
            ("cw_scan_a", mul(lanes, 8, "closed scan")?),
            ("cw_scan_b", mul(lanes, 8, "closed scan")?),
            ("cw_step", step_words.len() as u32),
            ("idle", 4),
        ] {
            let initial = match name {
                "cw_config" => Some(config.as_slice()),
                "cw_step" => Some(step_words.as_slice()),
                _ => None,
            };
            let use_flags = usage
                | if name == "cw_indirect" {
                    wgpu::BufferUsages::INDIRECT
                } else {
                    wgpu::BufferUsages::empty()
                };
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
        // One compute pass for the producer's waves, flushed before submit.
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
                .max(32),
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
        // Retained type height is bounded by 64. One final wave consumes
        // the leaf frontier; a pending frontier is a producer failure.
        for _ in 0..65 {
            producer.record(&mut encoder, 3, 1, store, &ext, 0)?;
            producer.record(&mut encoder, 4, 0, store, &ext, 0)?;
        }
        producer.record(&mut encoder, 5, terms, store, &ext, 0)?;
        producer.record(&mut encoder, 6, lanes, store, &ext, 0)?;
        for i in 0..steps.len() {
            producer.record(&mut encoder, 7, lanes, store, &ext, i as u32)?;
        }
        producer.record(&mut encoder, 8, 1, store, &ext, 0)?;
        passes_core::flush_deferred_compute(&mut encoder);
        drop(batch);
        queue.submit(Some(encoder.finish()));
        let state =
            producer
                .reader
                .read(&producer.buffers["cw_state"], 32, "closed trait demand")?;
        let mut report = ClosedTraitCheck {
            producer_failures: state[0],
            first_failure: state[1],
            rows: [0; TABLE_COUNT],
            batch_status: None,
        };
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
        let mut packet = self.gpu.new_packet()?;
        let (submission, offsets) = packet.packet.prepare_retained_submission(report.rows)?;
        config[68..86].copy_from_slice(&offsets);
        let uses = end;
        let obligations = report.rows[16];
        let atoms = add(catalog.slices[1].count, report.rows[1], "closed atoms")?;
        let use_map = RP_HEADER_WORDS;
        let route_rows = add(
            use_map,
            mul(uses, RP_USE_WORDS, "closed use map")?,
            "closed routes",
        )?;
        let atom_ids = add(
            route_rows,
            mul(obligations, RP_ROUTE_WORDS, "closed route rows")?,
            "closed ids",
        )?;
        let route_words = add(atom_ids, mul(atoms, 2, "closed ids")?, "closed route arena")?;
        let routes = Arena::uninitialized(&workspace, "closed.routes", route_words)?;
        config[10] = atom_ids;
        config[11] = use_map;
        producer.buffers["cw_config"].write(&queue, 0, &words_bytes(&config));
        // Source identity words live at a count-derived offset, not read
        // from a semantic row: source layout is fixed by its packet counts.
        let source_atom_ids = self.route_words - catalog.slices[1].count * 2;
        let catalog_buffer = self.gpu.storage.buffer.clone();
        let (readback, output_layout) =
            self.gpu
                .check_retained(&mut packet, &submission, false, |encoder, input| {
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
                    producer.record(encoder, 9, lanes, store, &ext, 0)
                })?;
        report.batch_status = Some(readback.batch_status);
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
        header[12] = obligations;
        header[13] = atoms;
        header[14] = use_map;
        header[15] = route_rows;
        header[16] = atom_ids;
        for (word, t) in [(17, 9), (18, 10), (27, 1), (28, 5), (29, 6)] {
            header[word] = catalog.slices[t].offset;
        }
        header[19] = catalog.slices[9].count;
        header[20] = catalog.slices[10].count;
        header[30] = report.rows[15];
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
        let mut encoder = device.create_command_encoder(&Default::default());
        routes.upload(
            &mut encoder,
            &[ArenaWrite {
                first_word: 0,
                words: header,
            }],
        )?;
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
        producer.record(
            &mut encoder,
            10,
            add(uses, obligations, "closed publication lanes")?,
            store,
            &ext,
            0,
        )?;
        producer.record(&mut encoder, 11, 1, store, &ext, 0)?;
        passes_core::flush_deferred_compute(&mut encoder);
        drop(batch);
        queue.submit(Some(encoder.finish()));
        // Finish before releasing the store lock or recycling producer scratch.
        let receipt = producer.reader.read(
            &routes.buffer,
            RP_HEADER_WORDS as usize,
            "closed publication receipt",
        )?;
        Ok((
            report,
            Some(ClosedTraitPublication {
                packet,
                routes,
                identity,
                proof_nodes: receipt[24],
            }),
        ))
    }
}
