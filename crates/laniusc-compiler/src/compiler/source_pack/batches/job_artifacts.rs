use super::*;

/// Builds a per-job artifact manifest from stored schedule and artifact-ref pages.
///
/// The job phase determines which output artifact is selected. Frontend and
/// codegen jobs also materialize interface dependency inputs from the stored
/// schedule dependency pages.
pub(in crate::compiler) fn job_artifact_manifest_from_stored_artifact_refs(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job: &SourcePackJob,
) -> Result<SourcePackJobArtifactManifest, CompileError> {
    validate_library_schedule_index(schedule_index, target)?;
    validate_artifact_ref_index(artifact_ref_index, target)?;
    let (
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interfaces,
        input_objects,
        outputs,
    ) = match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let (input_interface_count, input_interface_page_count, input_interface_ranges) =
                store_job_input_interface_pages(
                    store,
                    target,
                    schedule_index,
                    artifact_ref_index,
                    job.job_index,
                )?;
            (
                input_interface_count,
                input_interface_page_count,
                input_interface_ranges,
                Vec::new(),
                Vec::new(),
                vec![artifact_ref_for_index_from_stored_pages(
                    store,
                    target,
                    artifact_ref_index,
                    job.job_index,
                    SourcePackArtifactKind::LibraryInterface,
                )?],
            )
        }
        SourcePackJobPhase::Codegen => {
            let (input_interface_count, input_interface_page_count, input_interface_ranges) =
                store_job_input_interface_pages(
                    store,
                    target,
                    schedule_index,
                    artifact_ref_index,
                    job.job_index,
                )?;
            (
                input_interface_count,
                input_interface_page_count,
                input_interface_ranges,
                Vec::new(),
                Vec::new(),
                vec![artifact_ref_for_index_from_stored_pages(
                    store,
                    target,
                    artifact_ref_index,
                    job.job_index,
                    SourcePackArtifactKind::CodegenObject,
                )?],
            )
        }
        SourcePackJobPhase::Link => (
            0,
            0,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            vec![artifact_ref_for_index_from_stored_pages(
                store,
                target,
                artifact_ref_index,
                schedule_index.link_job_index,
                SourcePackArtifactKind::LinkedOutput,
            )?],
        ),
    };

    Ok(SourcePackJobArtifactManifest {
        job_index: job.job_index,
        phase: job.phase,
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interface_artifact_ranges: Vec::new(),
        input_interfaces,
        input_object_count: input_objects.len(),
        input_object_page_count: 0,
        input_object_artifact_ranges: Vec::new(),
        input_objects,
        outputs,
    })
}

/// Buffered writer for paged library-interface input refs of one job.
///
/// The writer converts dependency job indices into interface artifact refs and
/// flushes fixed-size sidecar pages when the inline page capacity is reached.
pub(in crate::compiler) struct JobInputInterfacePageWriter<'a> {
    /// Store receiving the sidecar pages.
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    /// Artifact target for the pages.
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    /// Job whose input-interface pages are being written.
    pub(in crate::compiler) job_index: usize,
    /// Artifact-ref index used to resolve dependency jobs into interface refs.
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    /// Next input-interface page index to write.
    pub(in crate::compiler) page_index: usize,
    /// First input position represented by the buffered page.
    pub(in crate::compiler) first_input_position: usize,
    /// Total number of input refs flushed so far.
    pub(in crate::compiler) input_count: usize,
    /// Buffered interface refs waiting for the next page flush.
    pub(in crate::compiler) current_input_interfaces: Vec<SourcePackArtifactRef>,
}

impl<'a> JobInputInterfacePageWriter<'a> {
    /// Creates an empty input-interface page writer for one job.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        job_index: usize,
        artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    ) -> Self {
        Self {
            store,
            target,
            job_index,
            artifact_ref_index,
            page_index: 0,
            first_input_position: 0,
            input_count: 0,
            current_input_interfaces: Vec::with_capacity(
                SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Adds the interface artifact produced by one dependency job.
    ///
    /// The artifact ref is loaded from the stored artifact-ref pages and the
    /// current page is flushed automatically when it reaches the configured cap.
    pub(in crate::compiler) fn push_job(
        &mut self,
        input_job_index: usize,
    ) -> Result<(), CompileError> {
        let artifact_ref = artifact_ref_for_index_from_stored_pages(
            self.store,
            self.target,
            self.artifact_ref_index,
            input_job_index,
            SourcePackArtifactKind::LibraryInterface,
        )?;
        self.current_input_interfaces.push(artifact_ref);
        if self.current_input_interfaces.len()
            == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    /// Writes the currently buffered input-interface refs as one sidecar page.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_input_interfaces.is_empty() {
            return Ok(());
        }
        let input_interfaces = std::mem::take(&mut self.current_input_interfaces);
        let page = SourcePackJobArtifactInputInterfacePage {
            version: SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION,
            target: self.target,
            job_index: self.job_index,
            page_index: self.page_index,
            first_input_position: self.first_input_position,
            input_count: input_interfaces.len(),
            input_interfaces,
        };
        validate_job_artifact_input_interface_page(
            &page,
            self.target,
            self.job_index,
            self.page_index,
        )?;
        self.store.store_job_artifact_input_interface_page(&page)?;
        self.input_count = self.input_count.saturating_add(page.input_count);
        self.first_input_position = self.first_input_position.saturating_add(page.input_count);
        self.page_index += 1;
        Ok(())
    }

    /// Flushes the final page and returns total input count and page count.
    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

/// Stores paged explicit interface inputs for one scheduled job.
///
/// Explicit dependency jobs are resolved and written to sidecar pages. Compact
/// dependency ranges are returned on the manifest instead of being expanded into
/// pages here.
pub(in crate::compiler) fn store_job_input_interface_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_index: usize,
) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
    let mut writer = JobInputInterfacePageWriter::new(store, target, job_index, artifact_ref_index);
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| {
            writer.push_job(dependency_job_index)?;
            Ok(())
        },
    )?;
    let (explicit_input_count, input_interface_page_count) = writer.finish()?;
    let ranged_input_count = job_index_range_dependency_count(&job_page.dependency_job_ranges);
    Ok((
        explicit_input_count.saturating_add(ranged_input_count),
        input_interface_page_count,
        job_page.dependency_job_ranges,
    ))
}
