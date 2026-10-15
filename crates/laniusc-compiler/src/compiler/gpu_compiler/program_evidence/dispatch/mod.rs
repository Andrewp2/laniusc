//! GPU catalog admission and persistent program storage.
//! Ordered batch admission, implementation selection, and replay validation.
mod arena;
mod workspace;
#[cfg(test)]
mod workspace_tests;
pub(in crate::compiler::gpu_compiler) use workspace::EvidenceWorkspacePool;
use workspace::WorkspaceLease;
#[cfg(test)]
mod batch_tests;
#[cfg(test)]
mod host_batch_tests;
mod kernels;
mod native_layout;
pub(super) use native_layout::{MaterializedProofType, NativeLayoutFailure};
mod proof;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod typed_constant_fault_tests;

use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};
use arena::Arena;

use super::{
    abi::*,
    catalog::FrozenCatalog,
    packet::{ProgramPacket, Submission, ValidatedEvidence},
    proof_store::{PROOF_STORE_FIXED_WORDS, PROOF_STORE_TABLES},
};
use crate::gpu::{
    buffers::LaniusBuffer,
    passes_core,
    readback::{PagedReadback, ReadbackRegion},
};

/// Constructed only after reading the exact proof arena and output arenas bound
/// to one submission. No public constructor accepts arbitrary receipt bytes.
/// It retains small receipts and root rows, never the complete proof graph.
pub(super) struct GpuProofReadback {
    epoch: u64,
    arena_id: u64,
    serial: u32,
    obligation_span: Span,
    receipt: [u32; 8],
    proof_header: Vec<u32>,
    obligations: Vec<[u32; 8]>,
    evidence: Vec<[u32; 8]>,
}
impl GpuProofReadback {
    pub(super) fn parts_for(
        &self,
        epoch: u64,
        arena_id: u64,
        serial: u32,
    ) -> Result<([u32; 8], &[u32])> {
        ensure!(
            self.epoch == epoch && self.arena_id == arena_id && self.serial == serial,
            "proof readback belongs to a different owned GPU submission"
        );
        Ok((self.receipt, &self.proof_header))
    }
    pub(super) fn root_for(
        &self,
        epoch: u64,
        arena_id: u64,
        serial: u32,
        obligation: u32,
    ) -> Result<([u32; 8], [u32; 8])> {
        self.parts_for(epoch, arena_id, serial)?;
        let index = obligation
            .checked_sub(self.obligation_span.first)
            .ok_or_else(|| anyhow!("proof root precedes this submission"))?;
        ensure!(
            index < self.obligation_span.count,
            "proof root is outside this submission"
        );
        let result = *self
            .obligations
            .get(index as usize)
            .ok_or_else(|| anyhow!("proof readback has no required source result"))?;
        let evidence = *self
            .evidence
            .get(index as usize)
            .ok_or_else(|| anyhow!("proof readback has no required root"))?;
        Ok((result, evidence))
    }
    pub(super) fn check_results(
        &self,
        submission: &Submission,
        receipt: [u32; 8],
        obligations: &[[u32; 8]],
        evidence: &[[u32; 8]],
    ) -> Result<()> {
        self.parts_for(submission.epoch, submission.arena_id, submission.serial)?;
        ensure!(
            (self.obligation_span.first, self.obligation_span.count)
                == (
                    submission.obligation_span.first,
                    submission.obligation_span.count
                )
                && self.receipt == receipt
                && self.obligations == obligations
                && self.evidence == evidence,
            "root result rows are not from the retained proof arena readback"
        );
        Ok(())
    }
}

/// One admitted frozen catalog and its device/queue ownership. No independent
/// catalog cache; this object lives inside the existing program compilation job.
/// Successful construction is the sole transition that freezes GPU catalog data.
pub(super) struct GpuProgramEvidence {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    workspace: WorkspaceLease,
    catalog: Arc<FrozenCatalog>,
    gpu_owner: Arc<()>,
    storage: Arena,
    native_recipes: Arena,
    readback: PagedReadback,
    batch_kernels: Option<kernels::BatchKernels>,
    proof_kernels: Option<kernels::ProofKernels>,
    layout_kernel: Option<kernels::NativeLayoutKernel>,
}

/// A host packet and precisely the GPU arenas that contain its row closure.
/// Failed submissions poison this object; it cannot lend another packet's bytes
/// to ProgramPacket::accept_submission or reuse an old successful receipt.
pub(super) struct GpuPacket {
    gpu_owner: Arc<()>,
    packet: ProgramPacket,
    input: Arena,
    output: Arena,
    proof: Arena,
    arena_id: Option<u64>,
    completed_serial: u32,
    completed_suffix_counts: [u32; TABLE_COUNT],
    /// Batch-arena word offset of each input table after the last accepted
    /// submission; see ensure_retained_inputs_unchanged.
    completed_input_offsets: [u32; TABLE_COUNT],
    poisoned: bool,
    /// Test-only: the next submission also re-uploads this retained input row.
    #[cfg(test)]
    retained_input_rewrite: std::cell::Cell<Option<(usize, u32)>>,
    #[cfg(test)]
    proof_admission_fault: std::cell::RefCell<Option<batch_tests::ProofAdmissionFault>>,
    #[cfg(test)]
    constant_admission_fault: std::cell::RefCell<Option<typed_constant_fault_tests::ConstantAdmissionFault>>,
}
impl GpuPacket {
    /// Descriptive source provenance remains readable after a failed batch;
    /// this accessor cannot admit rows or grant another replay capability.
    pub(super) fn failure_call_site(
        &self,
        failure: &EvidenceDispatchFailure,
    ) -> Option<super::packet::RetainedCallSite> {
        let call = if let Some((obligation, _)) = failure.obligation {
            // Failure payload words need not name the row. Use the dispatch
            // owner's retained row index, including Missing result payloads.
            self.packet.tables.row(16, obligation).ok()?[0]
        } else if let Some((call, _)) = failure.call {
            call
        } else if let Some((context, _)) = failure.context {
            self.packet.tables.row(13, context).ok()?[6]
        } else {
            return None;
        };
        self.packet.retained_call_site(call).ok()
    }
    /// Immutable retained metadata is descriptive even after a failed batch.
    /// It cannot advance admission or mint a replay capability.
    pub(super) fn packet(&self) -> &ProgramPacket {
        &self.packet
    }

    pub fn packet_mut(&mut self) -> Result<&mut ProgramPacket> {
        ensure!(
            !self.poisoned,
            "GPU evidence packet failed; discard this packet"
        );
        Ok(&mut self.packet)
    }
}

impl GpuProgramEvidence {
    pub fn admit(
        workspace: WorkspaceLease,
        catalog: Arc<FrozenCatalog>,
    ) -> Result<Self> {
        let device = workspace.device().clone();
        let queue = workspace.queue().clone();
        let limits = device.limits();
        ensure!(
            limits.max_storage_buffers_per_shader_stage >= 4
                && limits.max_uniform_buffers_per_shader_stage >= 2
                && limits.max_bindings_per_bind_group >= 6,
            "device cannot bind evidence arenas"
        );
        let kernels = kernels::CatalogKernels::load(&device)?;
        let storage = Arena::from_words(&workspace, "program_evidence.catalog", &catalog.words)?;
        let recipe_kernels = kernels::RecipeKernels::load(&device)?;
        // One-shot processes create these pipelines lazily; save driver
        // compiles now rather than only at a normal exit.
        crate::gpu::device::persist_created_pipelines_for_device(&device);
        let native_recipes = Arena::from_words(&workspace, "program_evidence.native_recipes", &catalog.native_layout.words)?;
        let (header, empty_output) = catalog_bootstrap(&catalog)?;
        let input = Arena::from_words(&workspace, "program_evidence.catalog_directory", &header)?;
        let output = Arena::from_words(&workspace, "program_evidence.catalog_output", &empty_output)?;
        let page_bytes = usize::try_from(limits.max_buffer_size.min(1 << 20))? & !3usize;
        ensure!(
            page_bytes >= 4,
            "device cannot allocate evidence readback page"
        );
        let readback = PagedReadback::from_staging(workspace.reserve("program_evidence.readback")?
            .buffer(u32::try_from(page_bytes / 4)?, wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, None)?
            .subrange::<u8>(0, page_bytes as u64, page_bytes).map_err(anyhow::Error::msg)?);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("program_evidence.admit_catalog"),
        });
        // Trusted serializer offsets; reset before initialize even when a future
        // upload policy recycles physical storage. Scratch gets full phase clears.
        passes_core::flush_deferred_compute(&mut encoder);
        for table in [0usize, 1] {
            let slice = catalog.outputs[table];
            if slice.count != 0 {
                storage.buffer.clear(
                    &mut encoder,
                    u64::from(slice.offset) * 4,
                    Some(u64::from(mul(slice.count, OUTPUT_WIDTHS[table], "catalog reset")?) * 4),
                );
            }
        }
        let recipe_status = catalog.native_layout.status;
        native_recipes.buffer.clear(&mut encoder, u64::from(recipe_status.offset) * 4, Some(32));
        kernels.record(&device, &mut encoder, &catalog, &storage, &input, &output)?;
        recipe_kernels.record(&device, &mut encoder, &catalog, &storage, &input, &output, &native_recipes)?;
        passes_core::flush_deferred_compute(&mut encoder);
        queue.submit(Some(encoder.finish()));
        let region = ReadbackRegion::from_buffer(
            &storage.buffer,
            u64::from(catalog.outputs[0].offset) * 4,
            32,
            "catalog receipt",
        )?;
        let recipe_region = ReadbackRegion::from_buffer(
            &native_recipes.buffer, u64::from(recipe_status.offset) * 4, 32, "native recipe receipt",
        )?;
        let raw = readback.read_regions(
            &device,
            &queue,
            &[region, recipe_region],
            "program evidence catalog and recipe receipts",
        )?;
        let status = one_status(&raw[0])?;
        ensure!(
            status[0] == 1,
            "program catalog GPU admission/coherence failed: {status:?}"
        );
        let recipe_status = one_status(&raw[1])?;
        ensure!(recipe_status[0] == 1,
            "program native recipe GPU admission failed: {recipe_status:?}");
        Ok(Self {
            device,
            queue,
            workspace,
            catalog,
            gpu_owner: Arc::new(()),
            storage,
            native_recipes,
            readback,
            batch_kernels: None,
            proof_kernels: None,
            layout_kernel: None,
        })
    }

    pub fn new_packet(&self) -> Result<GpuPacket> {
        Ok(GpuPacket {
            gpu_owner: self.gpu_owner.clone(),
            packet: ProgramPacket::new(self.catalog.clone())?,
            input: Arena::empty(&self.workspace, "program_evidence.batch_input")?,
            output: Arena::empty(&self.workspace, "program_evidence.batch_output")?,
            proof: Arena::empty(&self.workspace, "program_evidence.proof_store")?,
            arena_id: None,
            completed_serial: 0,
            completed_suffix_counts: [0; TABLE_COUNT],
            completed_input_offsets: [0; TABLE_COUNT],
            poisoned: false,
            #[cfg(test)]
            retained_input_rewrite: std::cell::Cell::new(None),
            #[cfg(test)]
            proof_admission_fault: std::cell::RefCell::new(None),
            #[cfg(test)]
            constant_admission_fault: std::cell::RefCell::new(None),
        })
    }

    fn prepare_proof_store(
        &self,
        packet: &mut GpuPacket,
        encoder: &mut wgpu::CommandEncoder,
        submission: &Submission,
        capacities: [u32; PROOF_STORE_TABLES],
    ) -> Result<()> {
        let upload = packet
            .packet
            .proof_store
            .grow(submission.serial, capacities)?;
        packet.proof.prepare(
            encoder,
            upload.layout.word_count,
            &upload.copies,
        )?;
        packet.proof.upload(
            encoder,
            &[ArenaWrite {
                first_word: 0,
                words: upload.header,
            }],
        )?;
        Ok(())
    }

    fn proof_progress(
        &self,
        packet: &GpuPacket,
        layout: &OutputLayout,
        submission: &Submission,
    ) -> Result<proof::ProofProgress> {
        let regions = [
            ReadbackRegion::from_buffer(
                &packet.proof.buffer,
                0,
                arena::byte_len(PROOF_STORE_FIXED_WORDS)?,
                "proof progress directory",
            )?,
            layout.region(&self.storage, &packet.output, 10, Span::new(0, 1)?)?,
        ];
        SOLVER_READBACKS.with(|count| count.set(count.get() + 1));
        let raw = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            "program proof progress counters",
        )?;
        let header = words(&raw[0])?;
        let receipt = one_status(&raw[1])?;
        proof::ProofProgress::from_owned_readback(
            packet.packet.proof_store.layout(),
            submission,
            header,
            receipt,
        )
    }

    fn submit_proof_progress(
        &self,
        packet: &GpuPacket,
        layout: &OutputLayout,
        submission: &Submission,
        mut encoder: wgpu::CommandEncoder,
    ) -> Result<proof::ProofProgress> {
        passes_core::flush_deferred_compute(&mut encoder);
        self.queue.submit(Some(encoder.finish()));
        self.proof_progress(packet, layout, submission)
    }

    /// Run GPU waves using only row counters. A stopped attempt returns its
    /// sticky GPU receipt; only an explicit table-capacity failure can retry.
    fn run_solver_attempt(
        &self,
        packet: &mut GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
        capacities: [u32; PROOF_STORE_TABLES],
        retry: bool,
    ) -> Result<Option<proof::ProofProgress>> {
        let batch = self.batch_kernels.as_ref().expect("loaded batch kernels");
        let solver = self.proof_kernels.as_ref().expect("loaded proof kernels");
        let encoder = || {
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("program_evidence.proof_wave"),
                })
        };
        let mut commands = encoder();
        self.prepare_proof_store(packet, &mut commands, submission, capacities)?;
        let resets = layout.reset_writes(submission)?;
        packet.output.upload(&mut commands, &resets)?;
        let mut attempt_plan = plan.clone();
        if retry {
            // A failed earlier phase15 may already have inserted new bucket
            // heads. Rebuild the entire temporary assumption index, retaining
            // all accepted input, output evidence, context and call rows.
            packet.output.upload(
                &mut commands,
                &layout.assumption_index_resets()?,
            )?;
            attempt_plan.assumption_index = Span::new(0, layout.input_suffix_counts[14])?;
        }
        let resources = kernels::ProofResources {
            storage: &packet.proof,
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
        };
        let record = |commands: &mut wgpu::CommandEncoder, phase: u32, span: Span| {
            solver.record(
                &self.device,
                commands,
                phase,
                span,
                &self.storage,
                &packet.input,
                &packet.output,
                resources,
            )
        };
        let one = Span::new(0, 1)?;
        batch.record_initialize(
            &self.device,
            &mut commands,
            &self.storage,
            &packet.input,
            &packet.output,
            resources,
        )?;
        record(&mut commands, 40, one)?;
        batch.record_before_solver(
            &self.device,
            &mut commands,
            &attempt_plan,
            &self.storage,
            &packet.input,
            &packet.output,
            resources,
        )?;
        record(&mut commands, 48, plan.obligations)?;
        if self.solver_waves(packet)? {
            return self.run_solver_waves(packet, layout, plan, submission, resources, commands);
        }
        let mut progress = self.submit_proof_progress(packet, layout, submission, commands)?;
        if !progress.is_building() {
            return Ok(Some(progress));
        }
        let mut commands = encoder();
        record(&mut commands, 49, progress.pending(proof::WORK)?)?;
        record(&mut commands, 50, one)?;
        progress = self.submit_proof_progress(packet, layout, submission, commands)?;
        if !progress.is_building() {
            return Ok(Some(progress));
        }

        let mut work_cursor = 0u32;
        let mut requirement_cursor = 0u32;
        let mut queue_cursor = 0u32;
        loop {
            let work = progress.appended(proof::WORK, work_cursor)?;
            if work.count != 0 {
                let requirements = progress.appended(9, requirement_cursor)?;
                let requirement_end = progress.admitted[9];
                let mut commands = encoder();
                #[cfg(test)]
                {
                    if typed_constant_fault_tests::needs_normalization_boundary(packet) {
                        // Ordinary replay faults pause after emission. The
                        // targeted binding ABI fixture pauses after term
                        // commit, before GPU goal hashing/admission.
                        let binding_recipe = typed_constant_fault_tests::needs_binding_recipe_boundary(packet);
                        let last = if binding_recipe { 45 } else { 42 };
                        for phase in 41..=last {
                            record(&mut commands, phase, if phase == 45 { one } else { work })?;
                        }
                        progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                        if !progress.is_building() { return Ok(Some(progress)); }
                        if binding_recipe {
                            typed_constant_fault_tests::seed_binding_projection_recipe(self, packet, &progress, work)?;
                        } else {
                            typed_constant_fault_tests::inspect_pending_normalization(self, packet, layout, &progress)?;
                        }
                        commands = encoder();
                        let first = if binding_recipe { 46 } else { 43 };
                        for phase in first..=47 {
                            record(&mut commands, phase, if matches!(phase, 45 | 47) { one } else { work })?;
                        }
                    } else {
                        solver.record_normalization(
                            &self.device,
                            &mut commands,
                            work,
                            &self.storage,
                            &packet.input,
                            &packet.output,
                            resources,
                        )?;
                    }
                }
                #[cfg(not(test))]
                solver.record_normalization(
                    &self.device,
                    &mut commands,
                    work,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                record(&mut commands, 51, work)?;
                record(&mut commands, 52, work)?;
                // Only requirements whose children just normalized may link.
                // A prior already-notified representative is handled on GPU.
                record(&mut commands, 57, requirements)?;
                solver.record_selection(
                    &self.device,
                    &mut commands,
                    work,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                if !progress.is_building() {
                    return Ok(Some(progress));
                }
                requirement_cursor = requirement_end;
                #[cfg(test)]
                typed_constant_fault_tests::inject_pending_substitution_fault(self, packet, layout, &progress)?;
                let mut commands = encoder();
                solver.record_substitutions(
                    &self.device,
                    &mut commands,
                    work,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                solver.record_binding_rows(
                    &self.device,
                    &mut commands,
                    progress.pending(5)?,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                record(&mut commands, 55, one)?;
                record(&mut commands, 56, work)?;
                progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                if !progress.is_building() {
                    return Ok(Some(progress));
                }
                let mut commands = encoder();
                record(&mut commands, 49, progress.pending(proof::WORK)?)?;
                record(&mut commands, 50, one)?;
                progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                if !progress.is_building() {
                    return Ok(Some(progress));
                }
                work_cursor = add(work.first, work.count, "normalized work cursor")?;
            }
            let queue = progress.appended(proof::QUEUE, queue_cursor)?;
            if queue.count != 0 {
                // Consume this immutable prefix only. Notifications appended by
                // this wave are scheduled from the next counter readback.
                let mut commands = encoder();
                record(&mut commands, 58, queue)?;
                progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                if !progress.is_building() {
                    return Ok(Some(progress));
                }
                #[cfg(test)]
                batch_tests::inject_pending_proof_fault(self, packet, layout, &progress)?;
                let mut commands = encoder();
                solver.record_implementation_proofs(
                    &self.device,
                    &mut commands,
                    queue,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                // Both proof kinds inspect the frozen pending wave before
                // any proof or edge prefix gains admitted authority.
                solver.record_assumption_proofs(
                    &self.device,
                    &mut commands,
                    queue,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                solver.record_proof_edge_rows(
                    &self.device,
                    &mut commands,
                    progress.pending(7)?,
                    &self.storage,
                    &packet.input,
                    &packet.output,
                    resources,
                )?;
                record(&mut commands, 60, one)?;
                record(&mut commands, 61, queue)?;
                record(&mut commands, 62, queue)?;
                record(&mut commands, 63, one)?;
                progress = self.submit_proof_progress(packet, layout, submission, commands)?;
                if !progress.is_building() {
                    return Ok(Some(progress));
                }
                queue_cursor = add(queue.first, queue.count, "reduced work queue cursor")?;
            }
            if work_cursor == progress.admitted[proof::WORK]
                && queue_cursor == progress.admitted[proof::QUEUE]
            {
                ensure!(
                    requirement_cursor == progress.admitted[9],
                    "solver reached quiescence with an unlinked requirement suffix"
                );
                break;
            }
        }
        let mut commands = encoder();
        // The GPU classifies unresolved finite cycles and missing leaves and
        // checks every source obligation before the native publication gate.
        record(&mut commands, 64, Span::new(0, progress.admitted[13])?)?;
        batch.record_after_solver(
            &self.device,
            &mut commands,
            plan,
            &self.storage,
            &packet.input,
            &packet.output,
            resources,
        )?;
        passes_core::flush_deferred_compute(&mut commands);
        self.queue.submit(Some(commands.finish()));
        Ok(None)
    }

    /// The GPU-planned rounds replace the stepped loop unless
    /// LANIUS_PEV_STEPPED_SOLVER=1, a dispatch capture is selected (the CPU
    /// replay tool reads ordinary parameter blocks), or a test fault hook
    /// needs a host boundary between steps.
    fn solver_waves(&self, packet: &GpuPacket) -> Result<bool> {
        if crate::gpu::env::env_bool_truthy("LANIUS_PEV_STEPPED_SOLVER", false)
            || std::env::var_os("LANIUS_DEBUG_CAPTURE_PASS").is_some()
        {
            return Ok(false);
        }
        #[cfg(test)]
        if packet.constant_admission_fault.borrow().is_some()
            || packet.proof_admission_fault.borrow().is_some()
        {
            return Ok(false);
        }
        let _ = packet;
        self.proof_kernels.as_ref().expect("loaded proof kernels").waves_supported()
    }

    /// The loop of run_solver_attempt with many rounds recorded per submit.
    /// The GPU planner takes each decision the host took from a counter
    /// readback (proof_solver_wave.slang), so the host reads back only when
    /// the recorded rounds run out, a span outgrows its recorded chunk steps,
    /// or the solver stops.
    fn run_solver_waves(
        &self,
        packet: &GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
        resources: kernels::ProofResources<'_>,
        mut commands: wgpu::CommandEncoder,
    ) -> Result<Option<proof::ProofProgress>> {
        use kernels::{WavePoint, wave};
        let batch = self.batch_kernels.as_ref().expect("loaded batch kernels");
        let solver = self.proof_kernels.as_ref().expect("loaded proof kernels");
        let encoder = || {
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("program_evidence.proof_wave"),
                })
        };
        let debug = crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_SOLVER_WAVES", false);
        let state = kernels::wave_state(&self.device, &self.storage)?;
        let chunks = |rows: u32| {
            rows.div_ceil(kernels::THREAD_SCRATCH_SLOTS)
                .max(1)
                .checked_next_power_of_two()
                .unwrap_or(kernels::WAVE_MAX_CHUNKS)
                .min(kernels::WAVE_MAX_CHUNKS)
        };
        let template = |points: &[WavePoint], chunks: u32| {
            solver.wave_template(&self.device, points, chunks, &state, &self.storage,
                &packet.input, &packet.output, resources)
        };
        // Later rounds record one chunk step per span. A longer span stops the
        // rounds at its point, and the rest of that round is recorded again
        // with enough chunk steps.
        let regular = template(&WavePoint::ROUND, 1)?;
        // The first work and the first round span every source obligation.
        let opening_chunks = chunks(plan.obligations.count);
        let first = template(&[WavePoint::FirstWork], opening_chunks)?;
        let opening = if opening_chunks > 1 {
            Some(template(&WavePoint::ROUND, opening_chunks)?)
        } else {
            None
        };
        solver.record_wave(&mut commands, &first);
        let opening = opening.as_ref().unwrap_or(&regular);
        solver.record_wave(&mut commands, opening);
        let mut rounds = 15u32;
        let mut dispatches = first.dispatches + opening.dispatches;
        let mut submits = 0u32;
        loop {
            for _ in 0..rounds {
                solver.record_wave(&mut commands, &regular);
            }
            dispatches += rounds as usize * regular.dispatches;
            passes_core::flush_deferred_compute(&mut commands);
            self.queue.submit(Some(commands.finish()));
            submits += 1;
            let (progress, words) = self.wave_progress(packet, layout, submission, &state)?;
            if debug {
                eprintln!(
                    "[lanius-pev] solver wave submit {submits}: stop={} detail={} rounds={} \
                     overflow_point={} overflow_rows={} recorded_dispatches={dispatches}",
                    words[wave::STOP],
                    words[wave::FAULT_DETAIL],
                    words[wave::ROUNDS],
                    words[wave::OVERFLOW_POINT],
                    words[wave::OVERFLOW_ROWS],
                );
            }
            if words[wave::STOP] == wave::FAULT {
                return Err(anyhow!(match words[wave::FAULT_DETAIL] {
                    wave::FAULT_IDENTITY => "solver progress belongs to another physical submission",
                    wave::FAULT_LAYOUT => "solver progress exceeds reserved physical storage",
                    wave::FAULT_RECEIPT => "solver progress has a stale or malformed batch receipt",
                    wave::FAULT_CURSOR => "solver work cursor moved beyond admitted rows",
                    wave::FAULT_REQUIREMENTS => {
                        "solver reached quiescence with an unlinked requirement suffix"
                    }
                    _ => "solver wave planner reported an unknown fault",
                }));
            }
            if !progress.is_building() {
                return Ok(Some(progress));
            }
            commands = encoder();
            dispatches = 0;
            match words[wave::STOP] {
                wave::DONE => {
                    ensure!(
                        words[wave::WORK_CURSOR] == progress.admitted[proof::WORK]
                            && words[wave::QUEUE_CURSOR] == progress.admitted[proof::QUEUE]
                            && words[wave::REQUIREMENT_CURSOR] == progress.admitted[9],
                        "solver wave finished before quiescence"
                    );
                    // The GPU classifies unresolved finite cycles and missing
                    // leaves and checks every source obligation before the
                    // native publication gate.
                    solver.record(
                        &self.device,
                        &mut commands,
                        64,
                        Span::new(0, progress.admitted[13])?,
                        &self.storage,
                        &packet.input,
                        &packet.output,
                        resources,
                    )?;
                    batch.record_after_solver(
                        &self.device,
                        &mut commands,
                        plan,
                        &self.storage,
                        &packet.input,
                        &packet.output,
                        resources,
                    )?;
                    passes_core::flush_deferred_compute(&mut commands);
                    self.queue.submit(Some(commands.finish()));
                    return Ok(None);
                }
                wave::OVERFLOW => {
                    let point = WavePoint::from_word(words[wave::OVERFLOW_POINT])
                        .ok_or_else(|| anyhow!("solver wave overflowed at an unknown point"))?;
                    let partial = template(point.remainder(), chunks(words[wave::OVERFLOW_ROWS]))?;
                    // The point plans again from the same counters.
                    state.write(&self.queue, 0, &wave::RUNNING.to_le_bytes());
                    if debug {
                        eprintln!(
                            "[lanius-pev] solver wave resumes at {point:?} with {} chunk steps",
                            partial.chunks
                        );
                    }
                    solver.record_wave(&mut commands, &partial);
                    dispatches += partial.dispatches;
                }
                wave::RUNNING => rounds = (rounds * 2).min(64),
                wave::STOPPED => {
                    return Err(anyhow!("solver wave stopped while the batch and store are building"));
                }
                stop => return Err(anyhow!("solver wave reported an unknown state {stop}")),
            }
        }
    }

    fn wave_progress(
        &self,
        packet: &GpuPacket,
        layout: &OutputLayout,
        submission: &Submission,
        state: &LaniusBuffer<u32>,
    ) -> Result<(proof::ProofProgress, Vec<u32>)> {
        let regions = [
            ReadbackRegion::from_buffer(
                &packet.proof.buffer,
                0,
                arena::byte_len(PROOF_STORE_FIXED_WORDS)?,
                "proof progress directory",
            )?,
            layout.region(&self.storage, &packet.output, 10, Span::new(0, 1)?)?,
            ReadbackRegion::from_buffer(
                state,
                0,
                arena::byte_len(kernels::wave::READ_WORDS)?,
                "solver wave state",
            )?,
        ];
        SOLVER_READBACKS.with(|count| count.set(count.get() + 1));
        let raw = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            "program proof wave progress",
        )?;
        let header = words(&raw[0])?;
        let receipt = one_status(&raw[1])?;
        let state = words(&raw[2])?;
        let progress = proof::ProofProgress::from_owned_readback(
            packet.packet.proof_store.layout(),
            submission,
            header,
            receipt,
        )?;
        Ok((progress, state))
    }

    /// Gate before body reuse/specialization and after each replay's fresh calls.
    /// A valid catalog does not bypass batch checking, including an empty delta.
    pub fn check(&mut self, packet: &mut GpuPacket) -> Result<Vec<ValidatedEvidence>> {
        ensure!(
            !packet.poisoned,
            "GPU evidence packet failed; discard this packet"
        );
        ensure!(
            Arc::ptr_eq(&packet.gpu_owner, &self.gpu_owner),
            "GPU packet belongs to another device/dispatch owner"
        );
        ensure!(
            Arc::ptr_eq(&packet.packet.catalog, &self.catalog),
            "GPU packet belongs to another immutable catalog object"
        );
        // Resolve every phase before advancing host packet state; artifact or
        // pipeline failure cannot leave a pending packet submission.
        if self.batch_kernels.is_none() {
            self.batch_kernels = Some(kernels::BatchKernels::load(&self.device)?);
        }
        if self.proof_kernels.is_none() {
            self.proof_kernels = Some(kernels::ProofKernels::load(&self.device)?);
        }
        crate::gpu::device::persist_created_pipelines_for_device(&self.device);
        let submission = packet.packet.prepare_submission()?;
        // Any transfer, dispatch, map, or semantic failure terminates this arena.
        // In particular a map error may not expose a stale prior successful row.
        packet.poisoned = true;
        ensure!(
            submission.epoch == self.catalog.epoch
                && submission.serial
                    == packet
                        .completed_serial
                        .checked_add(1)
                        .ok_or_else(|| anyhow!("GPU submission serial exhausted"))?,
            "GPU evidence submission identity changed"
        );
        match packet.arena_id {
            Some(id) => ensure!(
                id == submission.arena_id,
                "GPU packet arena identity changed"
            ),
            None => packet.arena_id = Some(submission.arena_id),
        }
        let layout = OutputLayout::from_submission(&self.catalog, &submission)?;
        let plan = BatchPlan::new(
            &self.catalog,
            &layout,
            packet.completed_suffix_counts,
            &submission,
        )?;
        #[cfg(test)]
        let submission = batch_tests::rewrite_retained_input(packet, &layout, submission)?;
        ensure_retained_inputs_unchanged(
            &layout,
            packet.completed_suffix_counts,
            packet.completed_input_offsets,
            &submission.plan,
        )?;
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("program_evidence.check_batch"),
            });
        packet.input.prepare(
            &mut encoder,
            submission.plan.input_word_count,
            &submission.plan.copies,
        )?;
        packet.output.prepare(
            &mut encoder,
            submission.plan.output_word_count,
            &submission.plan.output_copies,
        )?;
        packet
            .input
            .upload(&mut encoder, &submission.plan.writes)?;
        passes_core::flush_deferred_compute(&mut encoder);
        self.queue.submit(Some(encoder.finish()));
        let mut capacities = proof::initial_capacities(
            &packet.packet.proof_store,
            submission.obligation_span.count,
        )?;
        let mut retry = false;
        // LANIUS_DEBUG_SOLVER_WAVES=1 prints each solve's wall time and
        // counter readbacks.
        let solve_started = std::time::Instant::now();
        SOLVER_READBACKS.with(|count| count.set(0));
        let mut attempts = 0u32;
        loop {
            attempts += 1;
            let Some(stopped) =
                self.run_solver_attempt(packet, &layout, &plan, &submission, capacities, retry)?
            else {
                break;
            };
            let Some(grown) = stopped.capacity_retry(packet.packet.proof_store.layout())? else {
                break;
            };
            capacities = grown;
            retry = true;
        }
        if crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_SOLVER_WAVES", false) {
            eprintln!(
                "[lanius-pev] solve: {} attempts={attempts} readbacks={} wall={:.3}ms",
                if self.solver_waves(packet)? { "waves" } else { "stepped" },
                SOLVER_READBACKS.with(|count| count.get()),
                solve_started.elapsed().as_secs_f64() * 1000.0,
            );
        }

        // Exact arena association comes from these private owned buffers, not a
        // caller-supplied byte slice. One batched transfer reads all required rows.
        let regions = [
            layout.region(&self.storage, &packet.output, 0, Span::new(0, 1)?)?,
            layout.region(&self.storage, &packet.output, 10, Span::new(0, 1)?)?,
            layout.region(&self.storage, &packet.output, 2, submission.context_span)?,
            layout.region(&self.storage, &packet.output, 4, submission.call_span)?,
            layout.region(&self.storage, &packet.output, 3, submission.obligation_span)?,
            layout.region(&self.storage, &packet.output, 5, submission.obligation_span)?,
            ReadbackRegion::from_buffer(
                &packet.proof.buffer,
                0,
                arena::byte_len(PROOF_STORE_FIXED_WORDS)?,
                "accepted proof directory",
            )?,
        ];
        let raw = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            "program evidence batch receipt and results",
        )?;
        let catalog_status = one_status(&raw[0])?;
        let batch_status = one_status(&raw[1])?;
        let contexts = statuses(&raw[2])?;
        let calls = statuses(&raw[3])?;
        let obligations = statuses(&raw[4])?;
        let evidence = statuses(&raw[5])?;
        let proof_readback = GpuProofReadback {
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            obligation_span: submission.obligation_span,
            receipt: batch_status,
            proof_header: words(&raw[6])?,
            obligations: obligations.clone(),
            evidence: evidence.clone(),
        };
        let accepted = packet
            .packet
            .accept_submission(
                &submission,
                catalog_status,
                batch_status,
                &contexts,
                &calls,
                &obligations,
                &evidence,
                &proof_readback,
            )
            .map_err(|reason| {
                reason.context(EvidenceDispatchFailure::new(
                    &submission,
                    catalog_status,
                    batch_status,
                    &contexts,
                    &calls,
                    &obligations,
                ))
            })?;
        packet.completed_serial = submission.serial;
        // accept_submission appends returned Evidence17 to the host packet.
        // Those rows were NOT inputs to this dispatch; admit them next time.
        packet.completed_suffix_counts = layout.input_suffix_counts;
        packet.completed_input_offsets = layout.input_offsets;
        packet.poisoned = false;
        Ok(accepted)
    }
}

/// Transport-only validation of trusted serializer directories. Semantic graph,
/// parameter, implementation, ambiguity, and replay checks remain GPU-owned.
pub(super) struct OutputLayout {
    slices: [Slice; OUTPUT_COUNT],
    input_suffix_counts: [u32; TABLE_COUNT],
    input_offsets: [u32; TABLE_COUNT],
    input_capacities: [u32; TABLE_COUNT],
}
impl OutputLayout {
    fn from_submission(catalog: &FrozenCatalog, submission: &Submission) -> Result<Self> {
        let headers: Vec<_> = submission
            .plan
            .writes
            .iter()
            .filter(|w| w.first_word == 0)
            .collect();
        ensure!(headers.len() == 1, "submission needs one directory upload");
        let header = &headers[0].words;
        ensure!(
            header.len() == BATCH_FIXED_WORDS as usize
                && header[..8]
                    == [
                        MAGIC,
                        VERSION,
                        catalog.epoch as u32,
                        (catalog.epoch >> 32) as u32,
                        submission.serial,
                        TABLE_COUNT as u32,
                        DIRECTORY_WORD,
                        OUTPUT_DIRECTORY_WORD
                    ],
            "submission header mismatch"
        );
        let catalog_words = u32_len(catalog.words.len(), "catalog words")?;
        let mut counts = [0; TABLE_COUNT];
        let mut offsets = [0; TABLE_COUNT];
        let mut capacities = [0; TABLE_COUNT];
        for table in 0..TABLE_COUNT {
            let first = DIRECTORY_WORD as usize + table * 6;
            let row = &header[first..first + 6];
            let c = catalog.slices[table];
            ensure!(
                row[0] == c.offset && row[1] == c.count && row[5] == WIDTHS[table],
                "submission changed frozen catalog directory"
            );
            ensure!(
                row[3] <= row[4]
                    && row[2] <= submission.plan.input_word_count
                    && mul(row[4], row[5], "batch table capacity")?
                        <= submission.plan.input_word_count - row[2],
                "batch table exceeds arena allocation"
            );
            counts[table] = row[3];
            offsets[table] = row[2];
            capacities[table] = row[4];
        }
        let index_rows = catalog.slices[1].count.max(catalog.slices[9].count);
        let expected = [
            1,
            catalog.slices[9].count,
            counts[13],
            counts[16],
            counts[15],
            counts[16],
            index_rows,
            buckets(index_rows)?,
            counts[14],
            buckets(counts[14])?,
            1,
            catalog.slices[9].count,
            buckets(index_rows)?,
        ];
        let mut slices = [Slice::default(); OUTPUT_COUNT];
        for table in 0..OUTPUT_COUNT {
            let first = OUTPUT_DIRECTORY_WORD as usize + table * 5;
            let row = &header[first..first + 5];
            let in_catalog = matches!(table, 0 | 1 | 6 | 7 | 11 | 12);
            let words = if in_catalog {
                catalog_words
            } else {
                submission.plan.output_word_count
            };
            ensure!(
                row[0] == if in_catalog { 0 } else { 1 },
                "wrong output arena"
            );
            ensure!(
                row[4] == OUTPUT_WIDTHS[table] && row[2] == expected[table] && row[2] <= row[3],
                "wrong output shape"
            );
            ensure!(
                (row[3] != 0 || row[1] == 0)
                    && row[1] <= words
                    && mul(row[3], row[4], "output capacity")? <= words - row[1],
                "output exceeds arena"
            );
            let s = Slice {
                offset: row[1],
                count: row[2],
                capacity: row[3],
            };
            if in_catalog {
                let c = catalog.outputs[table];
                ensure!(
                    (s.offset, s.count, s.capacity) == (c.offset, c.count, c.capacity),
                    "submission changed frozen catalog output location"
                );
            }
            slices[table] = s;
        }
        Ok(Self {
            slices,
            input_suffix_counts: counts,
            input_offsets: offsets,
            input_capacities: capacities,
        })
    }

    fn reset_writes(&self, submission: &Submission) -> Result<Vec<ArenaWrite>> {
        let mut writes = Vec::new();
        let mut receipt_resets = 0;
        for range in &submission.plan.initialize_outputs {
            let table = usize::try_from(range.table)?;
            ensure!(
                matches!(table, 2 | 3 | 4 | 5 | 8 | 9 | 10),
                "attempted frozen output reset"
            );
            let slice = self.slices[table];
            ensure!(
                range.first_row <= slice.count && range.row_count <= slice.count - range.first_row,
                "output reset exceeds logical rows"
            );
            if table == 10 {
                ensure!(
                    range.first_row == 0 && range.row_count == 1,
                    "incomplete batch receipt reset"
                );
                receipt_resets += 1;
            }
            let pattern: &[u32] = match table {
                2 | 3 | 4 => &[0, 0, INVALID, INVALID, 0, 0, 0, 0],
                5 => &[0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 0],
                8 => &[0, INVALID, INVALID, 0],
                9 => &[INVALID],
                10 => &[0, 0, INVALID, INVALID, 0, 0, submission.serial, 0],
                _ => unreachable!(),
            };
            ensure!(
                pattern.len() == OUTPUT_WIDTHS[table] as usize,
                "output reset width mismatch"
            );
            let words = mul(range.row_count, OUTPUT_WIDTHS[table], "output reset words")?;
            let mut data = Vec::new();
            data.try_reserve_exact(usize::try_from(words)?)?;
            for _ in 0..range.row_count {
                data.extend_from_slice(pattern);
            }
            writes.push(ArenaWrite {
                first_word: add(
                    slice.offset,
                    mul(range.first_row, OUTPUT_WIDTHS[table], "output reset offset")?,
                    "output reset address",
                )?,
                words: data,
            });
        }
        ensure!(
            receipt_resets == 1,
            "every submission must reset exactly one batch receipt"
        );
        Ok(writes)
    }

    fn assumption_index_resets(&self) -> Result<Vec<ArenaWrite>> {
        let mut writes = Vec::new();
        for table in [8usize, 9] {
            let slice = self.slices[table];
            let pattern: &[u32] = if table == 8 {
                &[0, INVALID, INVALID, 0]
            } else {
                &[INVALID]
            };
            let mut words = Vec::new();
            words.try_reserve_exact(usize::try_from(mul(
                slice.count,
                OUTPUT_WIDTHS[table],
                "retry assumption index words",
            )?)?)?;
            for _ in 0..slice.count {
                words.extend_from_slice(pattern);
            }
            writes.push(ArenaWrite {
                first_word: slice.offset,
                words,
            });
        }
        Ok(writes)
    }

    fn region<'a>(
        &self,
        catalog: &'a Arena,
        output: &'a Arena,
        table: usize,
        span: Span,
    ) -> Result<ReadbackRegion<'a>> {
        let slice = self.slices[table];
        ensure!(
            span.first <= slice.count && span.count <= slice.count - span.first,
            "result readback exceeds logical rows"
        );
        let first = add(
            slice.offset,
            mul(span.first, OUTPUT_WIDTHS[table], "result offset")?,
            "result address",
        )?;
        let words = mul(span.count, OUTPUT_WIDTHS[table], "result size")?;
        let source = if matches!(table, 0 | 1 | 6 | 7 | 11 | 12) {
            catalog
        } else {
            output
        };
        ReadbackRegion::from_buffer(
            &source.buffer,
            u64::from(first) * 4,
            arena::byte_len(words)?,
            "evidence results",
        )
    }
}

fn catalog_bootstrap(catalog: &FrozenCatalog) -> Result<(Vec<u32>, Vec<u32>)> {
    // Admission can run before original calls are appended. Empty batch-only
    // tables use a real one-bucket assumption index and a fresh zero receipt.
    let mut header = vec![
        MAGIC,
        VERSION,
        catalog.epoch as u32,
        (catalog.epoch >> 32) as u32,
        0,
        TABLE_COUNT as u32,
        DIRECTORY_WORD,
        OUTPUT_DIRECTORY_WORD,
    ];
    for table in 0..TABLE_COUNT {
        let s = catalog.slices[table];
        header.extend([s.offset, s.count, 0, 0, 0, WIDTHS[table]]);
    }
    for table in 0..OUTPUT_COUNT {
        if matches!(table, 0 | 1 | 6 | 7 | 11 | 12) {
            let s = catalog.outputs[table];
            header.extend([0, s.offset, s.count, s.capacity, OUTPUT_WIDTHS[table]]);
        } else {
            let (first, count) = if table == 9 {
                (0, 1)
            } else if table == 10 {
                (1, 1)
            } else {
                (0, 0)
            };
            header.extend([1, first, count, count, OUTPUT_WIDTHS[table]]);
        }
    }
    ensure!(
        header.len() == BATCH_FIXED_WORDS as usize,
        "catalog directory width changed"
    );
    Ok((header, vec![INVALID, 0, 0, INVALID, INVALID, 0, 0, 0, 0]))
}
thread_local! {
    /// Solver counter readbacks of the current check (debug output only).
    static SOLVER_READBACKS: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

fn words(bytes: &[u8]) -> Result<Vec<u32>> {
    ensure!(bytes.len() % 4 == 0, "partial GPU proof directory word");
    Ok(bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().expect("four-byte word")))
        .collect())
}
fn statuses(bytes: &[u8]) -> Result<Vec<[u32; 8]>> {
    ensure!(bytes.len() % 32 == 0, "partial GPU evidence result");
    Ok(bytes
        .chunks_exact(32)
        .map(|row| {
            std::array::from_fn(|i| {
                u32::from_le_bytes(row[i * 4..i * 4 + 4].try_into().expect("four-byte word"))
            })
        })
        .collect())
}
fn one_status(bytes: &[u8]) -> Result<[u32; 8]> {
    ensure!(bytes.len() == 32, "missing GPU evidence receipt");
    Ok(statuses(bytes)?[0])
}

const BATCH_INPUT_TABLES: [usize; 11] = [1, 5, 6, 7, 11, 12, 13, 14, 15, 16, 17];

/// Covers every appended row independently of whether any call consumes it.
/// This is transport coverage, not a host proof or implementation search.
#[derive(Clone)]
struct BatchPlan {
    input_spans: [Span; TABLE_COUNT],
    contexts: Span,
    calls: Span,
    obligations: Span,
    assumption_index: Span,
}
impl BatchPlan {
    fn new(
        catalog: &FrozenCatalog,
        layout: &OutputLayout,
        prior: [u32; TABLE_COUNT],
        submission: &Submission,
    ) -> Result<Self> {
        let mut input_spans = [Span::default(); TABLE_COUNT];
        for table in 0..TABLE_COUNT {
            let current = layout.input_suffix_counts[table];
            ensure!(
                current >= prior[table],
                "GPU evidence input suffix {table} shrank"
            );
            if !BATCH_INPUT_TABLES.contains(&table) {
                ensure!(
                    current == 0 && prior[table] == 0,
                    "catalog-only input has a batch suffix"
                );
                continue;
            }
            input_spans[table] = Span::new(
                add(
                    catalog.slices[table].count,
                    prior[table],
                    "new input first row",
                )?,
                current - prior[table],
            )?;
        }
        ensure_same_span(
            submission.context_span,
            input_spans[13],
            "context admission",
        )?;
        ensure_same_span(submission.call_span, input_spans[15], "call admission")?;
        ensure_same_span(
            submission.obligation_span,
            input_spans[16],
            "obligation admission",
        )?;
        let rebuild = buckets(prior[14])? != buckets(layout.input_suffix_counts[14])?;
        let assumption_index = if rebuild {
            Span::new(0, layout.input_suffix_counts[14])?
        } else {
            input_spans[14]
        };
        ensure_same_span(
            submission.assumption_index_span,
            assumption_index,
            "assumption index",
        )?;
        // Prior result/evidence rows are GPU provenance for retained Evidence17.
        // Only a bucket-count change may reset old assumption index rows; status,
        // goal-cache, and evidence slots must never erase admitted old closures.
        for reset in &submission.plan.initialize_outputs {
            let table = usize::try_from(reset.table)?;
            let span = Span::new(reset.first_row, reset.row_count)?;
            let allowed = match table {
                2 => input_spans[13],
                3 | 5 => input_spans[16],
                4 => input_spans[15],
                8 => assumption_index,
                9 if rebuild || submission.serial == 1 => {
                    Span::new(0, buckets(layout.input_suffix_counts[14])?)?
                }
                9 => Span::default(),
                10 => Span::new(0, 1)?,
                _ => return Err(anyhow!("batch reset targets frozen output")),
            };
            ensure!(
                span.count == 0
                    || (span.first >= allowed.first
                        && span.first - allowed.first <= allowed.count
                        && span.count <= allowed.count - (span.first - allowed.first)),
                "batch reset overwrites retained output table {table}"
            );
        }
        // Exact reset coverage is enforced, not merely bounded. The serializer
        // currently emits one range per new region; a future split must still
        // cover the same rows exactly once without gaps or duplicates.
        for (table, expected) in [
            (2, input_spans[13]),
            (3, input_spans[16]),
            (4, input_spans[15]),
            (5, input_spans[16]),
            (8, assumption_index),
            (
                9,
                if rebuild || submission.serial == 1 {
                    Span::new(0, buckets(layout.input_suffix_counts[14])?)?
                } else {
                    Span::default()
                },
            ),
            (10, Span::new(0, 1)?),
        ] {
            let mut ranges: Vec<_> = submission
                .plan
                .initialize_outputs
                .iter()
                .filter(|r| r.table == table && r.row_count != 0)
                .collect();
            ranges.sort_unstable_by_key(|r| r.first_row);
            let mut cursor = expected.first;
            for range in ranges {
                ensure!(
                    range.first_row == cursor,
                    "output table {table} reset has a gap or overlap"
                );
                cursor = add(cursor, range.row_count, "output reset coverage")?;
            }
            ensure!(
                cursor == add(expected.first, expected.count, "expected reset end")?,
                "output table {table} was not completely initialized"
            );
        }
        Ok(Self {
            input_spans,
            contexts: submission.context_span,
            calls: submission.call_span,
            obligations: submission.obligation_span,
            assumption_index,
        })
    }
}
/// Retained input rows never change for the life of a packet. Later stages
/// trust what earlier submissions admitted and indexed: the caller-assumption
/// index (output tables 8 and 9) is rebuilt only when its bucket count changes,
/// and proof work selection and assumption-proof admission compare against its
/// hashes without admitting the predicate again. So a submission may only move
/// a table's retained rows unchanged (one relocation copy from the accepted
/// offset) and append rows after them, into input table regions that overlap
/// neither each other nor the fixed header.
fn ensure_retained_inputs_unchanged(
    layout: &OutputLayout,
    prior_counts: [u32; TABLE_COUNT],
    prior_offsets: [u32; TABLE_COUNT],
    plan: &UploadPlan,
) -> Result<()> {
    let mut regions = Vec::new();
    for table in BATCH_INPUT_TABLES {
        let capacity = mul(layout.input_capacities[table], WIDTHS[table], "input table capacity")?;
        if capacity != 0 {
            let offset = layout.input_offsets[table];
            regions.push((offset, add(offset, capacity, "input table end")?));
        }
    }
    regions.sort_unstable();
    ensure!(
        regions.first().is_none_or(|first| first.0 >= BATCH_FIXED_WORDS)
            && regions.windows(2).all(|pair| pair[0].1 <= pair[1].0),
        "batch input tables overlap each other or the header"
    );
    let mut moved = 0;
    for table in BATCH_INPUT_TABLES {
        let retained = mul(prior_counts[table], WIDTHS[table], "retained input words")?;
        if retained == 0 || layout.input_offsets[table] == prior_offsets[table] {
            continue;
        }
        ensure!(
            plan.copies.iter().any(|copy| copy.from_word == prior_offsets[table]
                && copy.to_word == layout.input_offsets[table]
                && copy.word_count == retained),
            "retained input table {table} moved without its rows"
        );
        moved += 1;
    }
    ensure!(
        plan.copies.iter().filter(|copy| copy.word_count != 0).count() == moved,
        "an input copy is not the relocation of a retained table"
    );
    for write in plan.writes.iter().filter(|write| write.first_word != 0) {
        let end = add(write.first_word, u32::try_from(write.words.len())?, "input write end")?;
        let mut appends = false;
        for table in BATCH_INPUT_TABLES {
            let offset = layout.input_offsets[table];
            let first = add(offset, mul(prior_counts[table], WIDTHS[table], "retained rows")?, "suffix")?;
            let last = add(offset, mul(layout.input_suffix_counts[table], WIDTHS[table], "rows")?, "end")?;
            appends |= write.first_word >= first && end <= last;
        }
        ensure!(appends, "submission rewrites retained input rows or writes outside a new suffix");
    }
    Ok(())
}
fn ensure_same_span(actual: Span, expected: Span, what: &str) -> Result<()> {
    ensure!(
        (actual.first, actual.count) == (expected.first, expected.count),
        "{what} span does not cover exactly the new rows"
    );
    Ok(())
}

/// Preserves the GPU's exact failure rows for source-diagnostic integration.
/// Receipt state6 is a summary: call and obligation rows retain Missing,
/// InvalidInput, ResourceLimit, Unsupported, and Ambiguous separately.
#[derive(Debug)]
pub(super) struct EvidenceDispatchFailure {
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
    pub catalog: [u32; 8],
    pub receipt: [u32; 8],
    pub context: Option<(u32, [u32; 8])>,
    pub call: Option<(u32, [u32; 8])>,
    pub obligation: Option<(u32, [u32; 8])>,
}
impl EvidenceDispatchFailure {
    fn new(
        submission: &Submission,
        catalog: [u32; 8],
        receipt: [u32; 8],
        contexts: &[[u32; 8]],
        calls: &[[u32; 8]],
        obligations: &[[u32; 8]],
    ) -> Self {
        // When the reducer reports a selection failure, prefer the precise rows
        // it names over a different thread's unprocessed/gated result.
        let preferred_call = if receipt[0] == 6 { receipt[2] } else { INVALID };
        let preferred_obligation = if receipt[0] == 6 { receipt[3] } else { INVALID };
        Self {
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            catalog,
            receipt,
            context: failure_row(contexts, submission.context_span, INVALID, false),
            call: failure_row(calls, submission.call_span, preferred_call, true),
            obligation: failure_row(
                obligations,
                submission.obligation_span,
                preferred_obligation,
                true,
            ),
        }
    }
}
fn failure_row(
    rows: &[[u32; 8]],
    span: Span,
    preferred: u32,
    permits_symbolic: bool,
) -> Option<(u32, [u32; 8])> {
    let failed = |row: &[u32; 8]| row[0] != 1 && (!permits_symbolic || row[0] != 2);
    if preferred >= span.first && preferred - span.first < span.count {
        if let Some(&row) = rows
            .get((preferred - span.first) as usize)
            .filter(|row| failed(row))
        {
            return Some((preferred, row));
        }
    }
    // Real terminal failures come before rows left unprocessed after a global
    // failure. GOAL_ADMITTED/BUILDING are unfinished, not a selection diagnosis.
    rows.iter()
        .enumerate()
        .find(|(_, row)| failed(row) && (2..=7).contains(&row[0]))
        .or_else(|| rows.iter().enumerate().find(|(_, row)| failed(row)))
        .map(|(offset, &row)| (span.first + offset as u32, row))
}
impl std::fmt::Display for EvidenceDispatchFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "GPU evidence rejected epoch {}, arena {}, serial {};",
            self.epoch, self.arena_id, self.serial
        )?;
        if let Some((row, status)) = self.obligation {
            write!(f, " obligation {row} {status:?};")?;
        }
        if let Some((row, status)) = self.call {
            write!(f, " call {row} {status:?};")?;
        }
        if let Some((row, status)) = self.context {
            write!(f, " context {row} {status:?};")?;
        }
        write!(f, " catalog {:?}; batch {:?}", self.catalog, self.receipt)
    }
}
impl std::error::Error for EvidenceDispatchFailure {}
