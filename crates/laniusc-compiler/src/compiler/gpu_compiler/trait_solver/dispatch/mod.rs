//! GPU catalog admission and persistent program storage.
//! Ordered batch admission, implementation selection, and replay validation.
mod arena;
mod workspace;
#[cfg(test)]
mod workspace_tests;
pub(in crate::compiler::gpu_compiler) use workspace::SolverWorkspacePool;
use workspace::WorkspaceLease;
#[cfg(test)]
mod batch_tests;
#[cfg(test)]
mod host_batch_tests;
mod solver_kernels;
mod native_layout;
pub(super) use native_layout::MaterializedProofType;
#[cfg(test)]
pub(super) use native_layout::NativeLayoutFailure;
mod implementation_application;
pub(super) use implementation_application::ProjectedImplApplication;
#[cfg(test)]
pub(super) use implementation_application::ImplProjectionLimits;
mod proof_progress;
mod retained_catalog;
pub(super) use retained_catalog::{
    check as retained_check,
    publish as retained_publish,
    record_count_follower as retained_count_follower,
};
pub use retained_catalog::{
    ClosedChainInputs,
    ClosedTraitCheck,
    ClosedTraitPublication,
    RETAINED_POISON,
    RetainedBufferRange,
    RetainedTraitCheck,
    RetainedTraitIdentity,
    RetainedTraitOptions,
    RetainedTraitPublication,
    RetainedTraitStage,
    RetainedTraitView,
};
#[cfg(test)]
mod tests;

use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};
use arena::Arena;

use super::{
    abi::*,
    catalog::FrozenCatalog,
    packet::{ProgramPacket, Submission, ValidatedSolverResult},
    proof_store::{PROOF_STORE_FIXED_WORDS, PROOF_STORE_TABLES},
};
use crate::gpu::{
    buffers::LaniusBuffer,
    passes_core,
    readback::{PagedReadback, ReadbackRegion},
};

/// Batch tables whose row counts a retained submission may take from the GPU
/// (record_gpu_batch_counts): the value-graph suffixes and tables 11-16.
const GPU_COUNTED_TABLES: [usize; 10] = [1, 5, 6, 7, 11, 12, 13, 14, 15, 16];
/// Output tables whose row count equals an input table's
/// (catalog_io.slang, ts_admit_output_layout): (output, input).
const GPU_COUNTED_OUTPUTS: [(usize, usize); 5] = [(2, 13), (3, 16), (4, 15), (5, 16), (8, 14)];

/// Records copies of a retained batch's row counts from the GPU into its
/// directory, so the solve takes them at dispatch time: `source` holds one
/// count per input table, table `t` at word `first_word + t`, written by
/// commands recorded before this call in the same submission.
///
/// The host plans the submission with upper bounds instead of counts
/// (`ProgramPacket::prepare_retained_submission(bounds)`): every table's
/// offset and capacity, the output layout and resets, the dispatch sizes
/// and the proof store come from the bounds. Each copied count replaces its
/// bound in the input directory (`DIRECTORY_WORD + 6 t + 3`) and in the
/// output directory of the tables that mirror it (`OUTPUT_DIRECTORY_WORD +
/// 5 o + 2`). Every solver kernel bounds its rows by these directory words
/// (`ts_table_count`), and batch initialization (12) rejects a count above
/// its capacity or an assumption count whose bucket count differs from the
/// bound's, so a wrong count fails the batch instead of reading other rows.
/// The host never reads the rows of such a solve: run it deferred.
pub(super) fn record_gpu_batch_counts(
    encoder: &mut wgpu::CommandEncoder,
    input: &Arena,
    source: &LaniusBuffer<u32>,
    first_word: u64,
) -> Result<()> {
    // The producer's dispatches may still be batched: they go first.
    passes_core::flush_deferred_compute(encoder);
    let word = |index: u64| index * 4;
    for table in GPU_COUNTED_TABLES {
        let to = u64::from(DIRECTORY_WORD) + table as u64 * 6 + 3;
        source.copy_to(encoder, word(first_word + table as u64), &input.buffer, word(to), 4);
    }
    for (output, table) in GPU_COUNTED_OUTPUTS {
        let to = u64::from(OUTPUT_DIRECTORY_WORD) + output as u64 * 5 + 2;
        source.copy_to(encoder, word(first_word + table as u64), &input.buffer, word(to), 4);
    }
    Ok(())
}

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
/// Construction submits the catalog's GPU admission, the sole transition that
/// freezes GPU catalog data; the first check reports a failed admission.
pub(super) struct GpuTraitSolver {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    workspace: WorkspaceLease,
    catalog: Arc<FrozenCatalog>,
    gpu_owner: Arc<()>,
    storage: Arena,
    native_recipes: Arena,
    readback: PagedReadback,
    batch_kernels: Option<solver_kernels::BatchKernels>,
    proof_kernels: Option<solver_kernels::ProofKernels>,
    layout_kernel: Option<solver_kernels::NativeLayoutKernel>,
    implementation_application_kernel: Option<solver_kernels::ImplementationApplicationKernel>,
    /// Reserved once per controller, not once per call/root. Query methods
    /// complete all readbacks before these exclusive roles can be reused.
    layout_query_slots: Vec<workspace::WorkspaceSlot>,
    implementation_query_slot: Option<workspace::WorkspaceSlot>,
    query_scratch_poisoned: bool,
    /// Catalog and native-recipe admission ran but no readback has read
    /// their receipts yet: the first check reads them with its results.
    admission_pending: std::sync::atomic::AtomicBool,
    /// Wave readbacks include the context, call, result and evidence rows.
    /// A retained publication clears it: its consumers bind the arenas.
    semantic_rows: bool,
    /// The wave state of the last solver attempt (solver_kernels::wave_state), for
    /// a deferred check that copies it out with a later readback.
    last_wave_state: std::sync::Mutex<Option<LaniusBuffer<u32>>>,
    /// A retained catalog's producer state: while the admission receipts
    /// are pending, the first wave readback reads it with them and leaves
    /// their verdict to the catalog (`WaveReadback::admission`).
    admission_state: std::sync::Mutex<Option<(LaniusBuffer<u32>, usize)>>,
    /// The input, output and proof roles of closed solves, and the token a
    /// live packet in them holds (`role_packet`). Closed waves solve one at
    /// a time, so each binds the buffers of the one before and its solver
    /// wave templates are found again (solver_kernels::wave_template).
    closed_role: (Arc<()>, [workspace::WorkspaceSlot; 3]),
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
    /// Held while this packet uses a controller's shared role.
    _role: Option<Arc<()>>,
    /// Test-only: the next submission also re-uploads this retained input row.
    #[cfg(test)]
    retained_input_rewrite: std::sync::Mutex<Option<(usize, u32)>>,
}
impl GpuPacket {
    #[cfg(test)]
    pub(super) fn uploaded_retained_evidence_rows(&self) -> u32 {
        self.completed_suffix_counts[17]
    }
    fn proof_resources(&self, submission: &Submission) -> solver_kernels::ProofResources<'_> {
        solver_kernels::ProofResources {
            storage: &self.proof,
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
        }
    }
    /// Descriptive source provenance remains readable after a failed batch;
    /// this accessor cannot admit rows or grant another replay capability.
    pub(super) fn failure_call_site(
        &self,
        failure: &SolverDispatchFailure,
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

/// Creates every trait-solver pipeline (the kernel caches keep them),
/// so that a daemon's jobs after readiness create none.
pub(in crate::compiler::gpu_compiler) fn prepare_kernels(device: &wgpu::Device) -> Result<()> {
    solver_kernels::CatalogKernels::load(device)?;
    solver_kernels::RecipeKernels::load(device)?;
    solver_kernels::BatchKernels::load(device)?;
    solver_kernels::ProofKernels::load(device)?;
    solver_kernels::NativeLayoutKernel::load(device)?;
    solver_kernels::ImplementationApplicationKernel::load(device)?;
    Ok(())
}

impl GpuTraitSolver {
    pub fn admit(
        workspace: WorkspaceLease,
        catalog: Arc<FrozenCatalog>,
    ) -> Result<Self> {
        ensure!(!catalog.is_retained(), "a GPU-produced catalog is admitted with its producer");
        let storage = Arena::from_words(&workspace, "trait_solver.catalog", &catalog.words)?;
        Self::admit_storage(workspace, catalog, storage, |_, _| Ok(()))
    }

    /// Admission of `catalog` in `storage`. `fill` records, before the
    /// admission kernels and in the same submit, the writes that complete
    /// the catalog rows (the retained producer, dispatch/retained_catalog/mod.rs).
    fn admit_storage(
        workspace: WorkspaceLease,
        catalog: Arc<FrozenCatalog>,
        storage: Arena,
        fill: impl FnOnce(&mut wgpu::CommandEncoder, &Arena) -> Result<()>,
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
        let kernels = solver_kernels::CatalogKernels::load(&device)?;
        let recipe_kernels = solver_kernels::RecipeKernels::load(&device)?;
        // One-shot processes create these pipelines lazily; save driver
        // compiles now rather than only at a normal exit.
        crate::gpu::device::persist_created_pipelines_for_device(&device);
        let native_recipes = Arena::from_words(&workspace, "trait_solver.native_recipes", &catalog.native_layout.words)?;
        let (header, empty_output) = catalog_bootstrap(&catalog)?;
        let input = Arena::from_words(&workspace, "trait_solver.catalog_directory", &header)?;
        let output = Arena::from_words(&workspace, "trait_solver.catalog_output", &empty_output)?;
        let page_bytes = usize::try_from(limits.max_buffer_size.min(1 << 20))? & !3usize;
        ensure!(
            page_bytes >= 4,
            "device cannot allocate evidence readback page"
        );
        let readback = workspace.readback("trait_solver.readback", page_bytes)?;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("trait_solver.admit_catalog"),
        });
        // Trusted serializer offsets; reset before initialize even when a future
        // upload policy recycles physical storage. Scratch gets full phase clears.
        fill(&mut encoder, &storage)?;
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
        // The first check reads both admission receipts with its results
        // (wave_readback), so the host appends calls while this runs.
        let closed_slots = [
            workspace.reserve("trait_solver.closed_input")?,
            workspace.reserve("trait_solver.closed_output")?,
            workspace.reserve("trait_solver.closed_proof")?,
        ];
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
            implementation_application_kernel: None,
            layout_query_slots: Vec::new(),
            implementation_query_slot: None,
            query_scratch_poisoned: false,
            admission_pending: std::sync::atomic::AtomicBool::new(true),
            semantic_rows: true,
            last_wave_state: std::sync::Mutex::new(None),
            admission_state: std::sync::Mutex::new(None),
            closed_role: (Arc::new(()), closed_slots),
        })
    }

    /// Admits `catalog` and checks a packet of its original calls, which
    /// reads the admission receipts: a failed admission is this call's error.
    #[cfg(test)]
    pub(super) fn admit_checked(workspace: WorkspaceLease, catalog: Arc<FrozenCatalog>) -> Result<Self> {
        let mut gpu = Self::admit(workspace, catalog.clone())?;
        let mut packet = gpu.new_packet()?;
        for snapshot in &catalog.snapshots {
            packet.packet_mut()?.append_original_unit_calls(&snapshot.original_facts)?;
        }
        gpu.check(&mut packet)?;
        Ok(gpu)
    }

    pub fn new_packet(&self) -> Result<GpuPacket> {
        self.packet_in(
            Arena::empty(&self.workspace, "trait_solver.batch_input")?,
            Arena::empty(&self.workspace, "trait_solver.batch_output")?,
            Arena::empty(&self.workspace, "trait_solver.proof_store")?,
            None,
        )
    }

    /// A packet in the closed-solve role when no packet holds it, else a
    /// packet of its own.
    pub fn role_packet(&self) -> Result<GpuPacket> {
        let (token, [input, output, proof]) = &self.closed_role;
        if Arc::strong_count(token) != 1 {
            return self.new_packet();
        }
        self.packet_in(
            Arena::from_slot_words(input, &[])?,
            Arena::from_slot_words(output, &[])?,
            Arena::from_slot_words(proof, &[])?,
            Some(token.clone()),
        )
    }

    fn packet_in(&self, input: Arena, output: Arena, proof: Arena, role: Option<Arc<()>>) -> Result<GpuPacket> {
        Ok(GpuPacket {
            gpu_owner: self.gpu_owner.clone(),
            packet: ProgramPacket::new(self.catalog.clone())?,
            input,
            output,
            proof,
            arena_id: None,
            completed_serial: 0,
            completed_suffix_counts: [0; TABLE_COUNT],
            completed_input_offsets: [0; TABLE_COUNT],
            poisoned: false,
            _role: role,
            #[cfg(test)]
            retained_input_rewrite: std::sync::Mutex::new(None),
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

    /// One solver attempt: the batch's admission, then the recorded steps.
    /// A stopped attempt returns its sticky GPU receipt; only an explicit
    /// table-capacity failure can retry.
    #[allow(clippy::too_many_arguments)]
    fn run_solver_attempt(
        &self,
        packet: &mut GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
        capacities: [u32; PROOF_STORE_TABLES],
        retry: bool,
        defer: bool,
    ) -> Result<Option<AttemptEnd>> {
        let batch = self.batch_kernels.as_ref().expect("loaded batch kernels");
        let mut commands = self.wave_encoder();
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
        // The setup dispatches share one compute pass, flushed by
        // submit_wave; no copy or clear is recorded among them.
        let deferred = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.proof_wave",
        );
        batch.record_initialize(
            &self.device,
            &mut commands,
            &self.storage,
            &packet.input,
            &packet.output,
            packet.proof_resources(submission),
        )?;
        batch.record_before_solver(
            &self.device,
            &mut commands,
            &attempt_plan,
            &self.storage,
            &packet.input,
            &packet.output,
            packet.proof_resources(submission),
        )?;
        let state = solver_kernels::wave_state(&self.storage, plan.obligations, plan.calls)?;
        *self.last_wave_state.lock().unwrap() = Some(state.clone());
        // The GPU admits the batch while the host records the steps.
        self.submit_wave(commands);
        drop(deferred);
        self.run_solver_waves(packet, layout, plan, submission, &state, defer)
    }

    fn wave_encoder(&self) -> wgpu::CommandEncoder {
        self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("trait_solver.proof_wave"),
        })
    }

    fn submit_wave(&self, mut commands: wgpu::CommandEncoder) {
        passes_core::flush_deferred_compute(&mut commands);
        self.queue.submit(Some(commands.finish()));
    }

    /// Records the solver's steps and reads its state back. A step runs up
    /// to 4096 Work rows through the two lane kernels, and the rows it
    /// appends run in a later step, so a solve takes one step per nesting
    /// level of its obligations or more (proof_work.slang). The planner
    /// chooses each step's rows on the GPU, and the finish publishes the
    /// roots and the batch receipt once no row is left. So the host reads
    /// back once per submit, and submits again only when rows were left.
    fn run_solver_waves(
        &self,
        packet: &mut GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
        state: &LaniusBuffer<u32>,
        defer: bool,
    ) -> Result<Option<AttemptEnd>> {
        use solver_kernels::wave;
        let solver = self.proof_kernels.as_ref().expect("loaded proof kernels");
        let program = solver.wave_program(
            &self.device,
            state,
            plan.obligations,
            plan.calls,
            &self.storage,
            &packet.input,
            &packet.output,
            packet.proof_resources(submission),
        )?;
        // A solve with no source obligation records one step, which finds no
        // row, and the finish.
        let mut steps = match plan.obligations.count {
            0 => 1,
            roots => roots.div_ceil(solver_kernels::THREAD_SCRATCH_SLOTS) + FIRST_SUBMIT_NESTED_STEPS,
        };
        loop {
            let mut commands = self.wave_encoder();
            solver.record_wave(&mut commands, &program, steps);
            self.submit_wave(commands);
            // A deferred check reads the state with its caller's readback.
            if defer {
                return Ok(None);
            }
            let readback = self.wave_readback(packet, layout, submission, state)?;
            if readback.state[wave::STOP] == wave::DONE {
                return Ok(Some(AttemptEnd { stopped: None, readback }));
            }
            let progress = readback.progress(packet, submission)?;
            if !progress.is_building() {
                return Ok(Some(AttemptEnd { stopped: Some(progress), readback }));
            }
            match readback.state[wave::STOP] {
                // Rows were left: twice the steps of the last submit, up to 64.
                wave::RUNNING => steps = (steps * 2).min(64),
                wave::STOPPED => {
                    return Err(anyhow!("solver wave stopped while the batch and store are building"));
                }
                stop => return Err(anyhow!("solver wave reported an unknown state {stop}")),
            }
        }
    }

    /// The one readback after a wave submit: the proof-store directory, the
    /// batch receipt and the planner state, then the check's result rows,
    /// final once the finish ran, and the catalog admission receipts until
    /// a check reads them.
    fn wave_readback(
        &self,
        packet: &GpuPacket,
        layout: &OutputLayout,
        submission: &Submission,
        state: &LaniusBuffer<u32>,
    ) -> Result<WaveReadback> {
        let mut regions = vec![
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
                arena::byte_len(solver_kernels::wave::READ_WORDS)?,
                "solver wave state",
            )?,
            layout.region(&self.storage, &packet.output, 0, Span::new(0, 1)?)?,
        ];
        if self.semantic_rows {
            regions.extend([
                layout.region(&self.storage, &packet.output, 2, submission.context_span)?,
                layout.region(&self.storage, &packet.output, 4, submission.call_span)?,
                layout.region(&self.storage, &packet.output, 3, submission.obligation_span)?,
                layout.region(&self.storage, &packet.output, 5, submission.obligation_span)?,
            ]);
        }
        let recipe_region = regions.len();
        let admission_pending = self.admission_pending.load(std::sync::atomic::Ordering::Relaxed);
        let admission_state = if admission_pending {
            self.admission_state.lock().unwrap().clone()
        } else {
            None
        };
        if admission_pending {
            let status = self.catalog.native_layout.status;
            regions.push(ReadbackRegion::from_buffer(
                &self.native_recipes.buffer,
                u64::from(status.offset) * 4,
                32,
                "native recipe receipt",
            )?);
        }
        if let Some((state, words)) = &admission_state {
            regions.push(ReadbackRegion::from_buffer(state, 0, arena::byte_len(u32::try_from(*words)?)?, "retained producer state")?);
        }
        let raw = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            crate::readback_label!("program proof wave progress"),
        )?;
        let catalog_status = one_status(&raw[3])?;
        let mut admission = None;
        // The catalog's admission ran in the first submit; its receipts come
        // with the first check's readback, before any batch result.
        if admission_state.is_some() {
            // The retained catalog judges its own receipts.
            admission = Some((one_status(&raw[recipe_region])?, words(&raw[recipe_region + 1])?));
            self.admission_pending.store(false, std::sync::atomic::Ordering::Relaxed);
        } else if admission_pending {
            ensure!(
                catalog_status[0] == 1,
                "program catalog GPU admission/coherence failed: {catalog_status:?}"
            );
            let recipe_status = one_status(&raw[recipe_region])?;
            ensure!(recipe_status[0] == 1,
                "program native recipe GPU admission failed: {recipe_status:?}");
            self.admission_pending.store(false, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(WaveReadback {
            admission,
            proof_header: words(&raw[0])?,
            batch_status: one_status(&raw[1])?,
            state: words(&raw[2])?,
            catalog_status,
            contexts: if self.semantic_rows { statuses(&raw[4])? } else { Vec::new() },
            calls: if self.semantic_rows { statuses(&raw[5])? } else { Vec::new() },
            obligations: if self.semantic_rows { statuses(&raw[6])? } else { Vec::new() },
            evidence: if self.semantic_rows { statuses(&raw[7])? } else { Vec::new() },
        })
    }

    /// The solver attempts of one check, retried with larger capacities
    /// only after an explicit table-capacity failure.
    fn solve(
        &self,
        packet: &mut GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
    ) -> Result<WaveReadback> {
        let mut capacities = proof_progress::with_floor(
            proof_progress::initial_capacities(&packet.packet.proof_store, submission.obligation_span.count)?,
            &self.workspace.proof_capacity_floor(),
            &packet.packet.proof_store,
        )?;
        let mut retry = false;
        loop {
            let end = self
                .run_solver_attempt(packet, layout, plan, submission, capacities, retry, false)?
                .ok_or_else(|| anyhow!("solver attempt deferred its readback"))?;
            let Some(stopped) = end.stopped else {
                return Ok(end.readback);
            };
            let Some(grown) = stopped.capacity_retry(&packet.packet.proof_store)? else {
                return Ok(end.readback);
            };
            PROOF_STORE_GROWTHS.with(|count| count.set(count.get() + 1));
            capacities = grown;
            retry = true;
        }
    }

    /// The first submit of `solve` without its readback: the caller reads
    /// the wave state later (`last_wave_state`) and retries eagerly when
    /// the solve did not finish in it.
    fn solve_deferred(
        &self,
        packet: &mut GpuPacket,
        layout: &OutputLayout,
        plan: &BatchPlan,
        submission: &Submission,
    ) -> Result<()> {
        let capacities = proof_progress::with_floor(
            proof_progress::initial_capacities(&packet.packet.proof_store, submission.obligation_span.count)?,
            &self.workspace.proof_capacity_floor(),
            &packet.packet.proof_store,
        )?;
        let end = self.run_solver_attempt(packet, layout, plan, submission, capacities, false, true)?;
        ensure!(end.is_none(), "a deferred solver attempt read its state");
        Ok(())
    }

    /// Gate before body reuse/specialization and after each replay's fresh calls.
    /// A valid catalog does not bypass batch checking, including an empty delta.
    pub fn check(&mut self, packet: &mut GpuPacket) -> Result<Vec<ValidatedSolverResult>> {
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
            self.batch_kernels = Some(solver_kernels::BatchKernels::load(&self.device)?);
        }
        if self.proof_kernels.is_none() {
            self.proof_kernels = Some(solver_kernels::ProofKernels::load(&self.device)?);
        }
        crate::gpu::device::persist_created_pipelines_for_device(&self.device);
        let prepare_span = crate::gpu::trace::HostSpan::new("host.compiler", "trait_solver.check.prepare");
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
                label: Some("trait_solver.check_batch"),
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
        drop(prepare_span);
        let solve_span = crate::gpu::trace::HostSpan::new("host.compiler", "trait_solver.check.solve");
        let result = self.solve(packet, &layout, &plan, &submission)?;
        let proof_layout = packet.packet.proof_store.layout();
        self.workspace.raise_proof_capacity_floor(
            &std::array::from_fn(|table| proof_layout.slices[table].capacity));

        drop(solve_span);
        let _accept_span = crate::gpu::trace::HostSpan::new("host.compiler", "trait_solver.check.results");
        // Exact arena association comes from these private owned buffers, not a
        // caller-supplied byte slice. The last wave readback read every required row.
        let WaveReadback {
            proof_header,
            batch_status,
            catalog_status,
            contexts,
            calls,
            obligations,
            evidence,
            ..
        } = result;
        let proof_readback = GpuProofReadback {
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            obligation_span: submission.obligation_span,
            receipt: batch_status,
            proof_header,
            obligations: obligations.clone(),
            evidence: evidence.clone(),
        };
        // A failure report names hard rows only: a soft-refuted call (status
        // 8) and its obligations read as successes there.
        let (failure_calls, failure_obligations) =
            without_soft_refutations(&packet.packet, &submission, &calls, &obligations);
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
                reason.context(SolverDispatchFailure::new(
                    &submission,
                    catalog_status,
                    batch_status,
                    &contexts,
                    &failure_calls,
                    &failure_obligations,
                ))
            })?;
        packet.completed_serial = submission.serial;
        // accept_submission appends returned table-17 rows to the host packet.
        // Those rows were NOT inputs to this dispatch; admit them next time.
        packet.completed_suffix_counts = layout.input_suffix_counts;
        packet.completed_input_offsets = layout.input_offsets;
        packet.poisoned = false;
        Ok(accepted)
    }
}

/// Steps the first submit records beyond those of the source obligations:
/// one per nesting level of prerequisites it can solve without a second
/// submit. A step past the last row launches no lane. Each further submit
/// costs a readback.
const FIRST_SUBMIT_NESTED_STEPS: u32 = 5;

/// How a solver attempt ended, with the readback of its last submit.
struct AttemptEnd {
    /// The decoded progress of an attempt whose batch or store stopped
    /// building; None for a solve the finish point published.
    stopped: Option<proof_progress::ProofProgress>,
    readback: WaveReadback,
}

/// The words of one wave readback (`GpuTraitSolver::wave_readback`).
struct WaveReadback {
    /// The native recipe receipt and the retained producer state, when this
    /// readback carried a retained catalog's admission (`admission_state`).
    admission: Option<([u32; 8], Vec<u32>)>,
    proof_header: Vec<u32>,
    batch_status: [u32; 8],
    state: Vec<u32>,
    catalog_status: [u32; 8],
    contexts: Vec<[u32; 8]>,
    calls: Vec<[u32; 8]>,
    obligations: Vec<[u32; 8]>,
    evidence: Vec<[u32; 8]>,
}
impl WaveReadback {
    /// The solver counters of a submit the finish point did not publish.
    fn progress(&self, packet: &GpuPacket, submission: &Submission) -> Result<proof_progress::ProofProgress> {
        proof_progress::ProofProgress::from_owned_readback(
            packet.packet.proof_store.layout(),
            submission,
            self.proof_header.clone(),
            self.batch_status,
        )
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
        let catalog_words = catalog.word_count()?;
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
    /// Proof-store growths (attempt retries with larger tables) on this thread,
    /// cumulative; tests read differences.
    static PROOF_STORE_GROWTHS: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// Proof-store growths on this thread so far (capacity retries).
#[cfg(test)]
pub(super) fn proof_store_growths() -> u64 {
    PROOF_STORE_GROWTHS.with(std::cell::Cell::get)
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
    /// Rows of each table's batch suffix, prior and new.
    suffix_rows: [u32; TABLE_COUNT],
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
        // Prior result/evidence rows are GPU provenance for retained table-17 rows.
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
            suffix_rows: layout.input_suffix_counts,
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
pub(super) struct SolverDispatchFailure {
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
    pub catalog: [u32; 8],
    pub receipt: [u32; 8],
    pub context: Option<(u32, [u32; 8])>,
    pub call: Option<(u32, [u32; 8])>,
    pub obligation: Option<(u32, [u32; 8])>,
}
/// Call and obligation statuses with every soft refutation read as success:
/// status 8 calls, and result-3 obligations of those calls.
fn without_soft_refutations(
    packet: &ProgramPacket,
    submission: &Submission,
    calls: &[[u32; 8]],
    obligations: &[[u32; 8]],
) -> (Vec<[u32; 8]>, Vec<[u32; 8]>) {
    let mut calls = calls.to_vec();
    let mut obligations = obligations.to_vec();
    let refuted = |call: u32| {
        call.checked_sub(submission.call_span.first)
            .and_then(|offset| calls.get(offset as usize))
            .is_some_and(|status| status[0] == 8)
    };
    for (i, status) in obligations.iter_mut().enumerate() {
        let obligation = submission.obligation_span.first + i as u32;
        let call = packet.tables.row(16, obligation).ok().map(|goal| goal[0]);
        if status[0] == 3 && call.is_some_and(|call| refuted(call)) {
            status[0] = 1;
        }
    }
    for status in &mut calls {
        if status[0] == 8 {
            status[0] = 1;
        }
    }
    (calls, obligations)
}

impl SolverDispatchFailure {
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
impl std::fmt::Display for SolverDispatchFailure {
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
impl std::error::Error for SolverDispatchFailure {}
