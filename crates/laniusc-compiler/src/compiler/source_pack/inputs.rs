use super::*;

/// In-memory library input used to build an [`ExplicitSourcePack`].
///
/// Dependencies are expressed by library id and are validated before the pack is
/// accepted. Source order within a library is preserved.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourceLibrary {
    pub library_id: u32,
    pub sources: Vec<String>,
    pub dependency_library_ids: Vec<u32>,
}

/// Path-backed library input used when all source paths are already materialized.
///
/// This shape is convenient for API callers that can provide a `Vec` of paths
/// for each library. Streaming variants below avoid requiring all paths or
/// dependency ids to be collected into vectors first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourceLibraryPaths<P> {
    pub library_id: u32,
    pub paths: Vec<P>,
    pub dependency_library_ids: Vec<u32>,
}

/// Streaming path-backed library input with vector-backed dependency ids.
///
/// `source_file_count` must match the number of paths yielded by `paths`; it is
/// used by planning code before the iterator is consumed.
#[derive(Debug)]
pub struct ExplicitSourceLibraryPathStream<I> {
    pub library_id: u32,
    pub source_file_count: usize,
    pub paths: I,
    pub dependency_library_ids: Vec<u32>,
}

/// Fully streaming path-backed library input.
///
/// This is the lowest-allocation caller input shape for persisted planning:
/// paths and dependency ids can both arrive from iterators while counts remain
/// available to validation and scheduling code.
#[derive(Debug)]
pub struct ExplicitSourceLibraryPathDependencyStream<PI, DI> {
    pub library_id: u32,
    pub source_file_count: usize,
    pub paths: PI,
    pub dependency_library_count: usize,
    pub dependency_library_ids: DI,
}

/// File metadata captured for a persisted source-pack input.
///
/// The planner records stable metadata up front so later preparation stages can
/// resume without rescanning all source files. `line_count == None` means the
/// file was not read while collecting metadata.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExplicitSourcePathFile {
    pub library_id: u32,
    pub path: PathBuf,
    pub byte_len: usize,
    pub modified_unix_nanos: Option<u128>,
    /// `None` means planning did not scan the file contents.
    pub line_count: Option<usize>,
}

/// Path-backed source-pack manifest used by persisted artifact builds.
///
/// This is the persisted-planning input equivalent of [`ExplicitSourcePack`]:
/// it stores file metadata rather than source strings, plus the validated
/// library dependency graph.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExplicitSourcePackPathManifest {
    pub files: Vec<ExplicitSourcePathFile>,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
}

/// In-memory source-pack input for planning and executing multi-library builds.
///
/// Each source has a library id at the same index in `library_ids`. Optional
/// source paths are diagnostic/provenance metadata; compilation still reads the
/// source text from `sources`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourcePack {
    pub sources: Vec<String>,
    pub source_paths: Vec<Option<PathBuf>>,
    pub library_ids: Vec<u32>,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
}

impl ExplicitSourcePack {
    /// Creates a pack from source strings and per-source library ids.
    ///
    /// The pack must contain at least one source and the two input vectors must
    /// have identical lengths.
    pub fn new(sources: Vec<String>, library_ids: Vec<u32>) -> Result<Self, CompileError> {
        if sources.is_empty() {
            return Err(CompileError::GpuFrontend(
                "explicit source pack has no source files".to_string(),
            ));
        }
        if sources.len() != library_ids.len() {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack has {} source files but {} library ids",
                sources.len(),
                library_ids.len()
            )));
        }
        Ok(Self {
            source_paths: vec![None; sources.len()],
            sources,
            library_ids,
            library_dependencies: Vec::new(),
        })
    }

    /// Attaches optional provenance paths to an existing in-memory pack.
    pub fn with_source_paths(
        mut self,
        source_paths: Vec<Option<PathBuf>>,
    ) -> Result<Self, CompileError> {
        if source_paths.len() != self.sources.len() {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack has {} source files but {} source paths",
                self.sources.len(),
                source_paths.len()
            )));
        }
        self.source_paths = source_paths;
        Ok(self)
    }

    /// Creates a pack that places every source in library id `0`.
    pub fn in_single_library(sources: Vec<String>) -> Result<Self, CompileError> {
        Self::from_libraries(vec![ExplicitSourceLibrary {
            library_id: 0,
            sources,
            dependency_library_ids: Vec::new(),
        }])
    }

    /// Flattens validated library inputs into a source-indexed pack.
    ///
    /// Libraries are accepted only when ids are unique, dependencies reference
    /// present libraries, and the dependency graph is acyclic.
    pub fn from_libraries(libraries: Vec<ExplicitSourceLibrary>) -> Result<Self, CompileError> {
        let library_entries = libraries
            .iter()
            .map(|library| ExplicitSourceLibraryManifestEntry {
                library_id: library.library_id,
                source_file_count: library.sources.len(),
                dependency_library_ids: library.dependency_library_ids.clone(),
            })
            .collect::<Vec<_>>();
        let (_, library_dependencies) = validate_explicit_source_library_entries(&library_entries)?;
        let source_count = library_entries
            .iter()
            .map(|library| library.source_file_count)
            .sum::<usize>();
        let mut sources = Vec::with_capacity(source_count);
        let mut library_ids = Vec::with_capacity(source_count);

        for library in libraries {
            for source in library.sources {
                sources.push(source);
                library_ids.push(library.library_id);
            }
        }

        let mut pack = Self::new(sources, library_ids)?;
        pack.library_dependencies = library_dependencies;
        Ok(pack)
    }

    /// Replaces the pack's dependency edges after validating them.
    ///
    /// This is useful when source strings are already flattened but library
    /// dependencies are discovered by a separate caller.
    pub fn with_library_dependencies(
        mut self,
        library_dependencies: Vec<SourcePackLibraryDependency>,
    ) -> Result<Self, CompileError> {
        let library_id_set = self.library_ids.iter().copied().collect::<BTreeSet<_>>();
        let mut seen_dependencies = BTreeSet::new();
        for dependency in &library_dependencies {
            if dependency.library_id == dependency.depends_on_library_id {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on itself",
                    dependency.library_id
                )));
            }
            if !library_id_set.contains(&dependency.library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack dependency references missing library {}",
                    dependency.library_id
                )));
            }
            if !library_id_set.contains(&dependency.depends_on_library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack dependency references missing library {}",
                    dependency.depends_on_library_id
                )));
            }
            if !seen_dependencies.insert((dependency.library_id, dependency.depends_on_library_id))
            {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack duplicate library dependency {} -> {}",
                    dependency.library_id, dependency.depends_on_library_id
                )));
            }
        }

        let library_ids = first_seen_library_ids(&self.library_ids);
        topologically_order_library_ids(&library_ids, &library_dependencies)?;
        self.library_dependencies = library_dependencies;
        Ok(self)
    }

    /// Plans backend codegen units over this in-memory pack.
    pub fn codegen_unit_plan(&self, limits: CodegenUnitLimits) -> CodegenUnitPlan {
        CodegenUnitPlan::from_source_pack_with_libraries(&self.sources, &self.library_ids, limits)
    }

    /// Plans frontend library-interface units over this in-memory pack.
    pub fn frontend_unit_plan(&self, limits: CodegenUnitLimits) -> FrontendUnitPlan {
        FrontendUnitPlan::from_source_pack_with_libraries(&self.sources, &self.library_ids, limits)
    }

    /// Builds the full source-pack job graph for the configured limits.
    pub fn job_plan(&self, limits: CodegenUnitLimits) -> SourcePackJobPlan {
        SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &self.sources,
            &self.library_ids,
            &self.library_dependencies,
            limits,
        )
    }

    /// Produces a topological job schedule for the full job graph.
    pub fn job_schedule(&self, limits: CodegenUnitLimits) -> SourcePackJobSchedule {
        self.job_plan(limits).job_schedule()
    }

    /// Produces a job schedule that keeps frontend jobs bounded by unit limits.
    pub fn bounded_frontend_job_schedule(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackJobSchedule {
        self.job_plan(limits).bounded_frontend_job_schedule()
    }

    /// Builds the default bounded-frontend artifact plan.
    pub fn build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.bounded_frontend_build_plan(limits)
    }

    /// Builds an artifact plan with one frontend job per whole library.
    pub fn whole_library_frontend_build_plan(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackBuildPlan {
        self.job_plan(limits).build_plan()
    }

    /// Builds an artifact plan whose frontend and codegen work respect limits.
    pub fn bounded_frontend_build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.job_plan(limits).bounded_frontend_build_plan()
    }

    /// Builds a compact generic-target artifact manifest for this pack.
    pub fn compact_build_artifact_manifest(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            limits,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    /// Builds a compact artifact manifest for a concrete target.
    pub fn compact_build_artifact_manifest_for_target(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        let plan = self.job_plan(limits);
        let schedule = plan.bounded_frontend_job_schedule();
        plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    /// Returns the source strings covered by a codegen unit.
    pub fn source_slice_for_unit(&self, unit: &CodegenUnit) -> &[String] {
        &self.sources[unit.source_range()]
    }

    /// Returns the source strings covered by a source-pack job.
    pub fn source_slice_for_job(&self, job: &SourcePackJob) -> &[String] {
        &self.sources[job.source_range()]
    }

    /// Returns the source strings covered by an artifact plan entry.
    pub fn source_slice_for_artifact(&self, artifact: &SourcePackArtifactPlan) -> &[String] {
        &self.sources[artifact.source_range()]
    }

    /// Executes the default bounded-frontend build plan with an in-memory executor.
    pub fn execute_build_plan<E>(
        &self,
        limits: CodegenUnitLimits,
        executor: &mut E,
    ) -> Result<
        BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: BuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_build(
            self,
            &build_plan,
            SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
            executor,
        )
    }

    /// Executes the bounded-frontend build plan with explicit batch limits.
    pub fn execute_build_plan_with_batch_limits<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<
        BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: BuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_build(self, &build_plan, batch_limits, executor)
    }
}

impl ExplicitSourcePackPathManifest {
    /// Collects path metadata from library path inputs in dependency order.
    ///
    /// The returned manifest validates the library graph and then records file
    /// metadata without loading source contents into memory.
    pub fn from_libraries<P>(
        libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    ) -> Result<Self, CompileError>
    where
        P: AsRef<Path>,
    {
        let library_entries = libraries
            .iter()
            .map(|library| ExplicitSourceLibraryManifestEntry {
                library_id: library.library_id,
                source_file_count: library.paths.len(),
                dependency_library_ids: library.dependency_library_ids.clone(),
            })
            .collect::<Vec<_>>();
        let (topological_library_ids, library_dependencies) =
            validate_explicit_source_library_entries(&library_entries)?;
        let source_file_count = library_entries
            .iter()
            .map(|library| library.source_file_count)
            .sum::<usize>();
        let mut files = Vec::with_capacity(source_file_count);
        let mut remaining_libraries = libraries.into_iter().map(Some).collect::<Vec<_>>();

        for library_id in topological_library_ids {
            let library_index = remaining_libraries
                .iter()
                .position(|library| {
                    library
                        .as_ref()
                        .is_some_and(|library| library.library_id == library_id)
                })
                .expect("topological library id must come from path manifest");
            let library = remaining_libraries[library_index]
                .take()
                .expect("topological library should be unconsumed");
            let label = format!("library {}", library.library_id);
            for (path_index, path) in library.paths.into_iter().enumerate() {
                files.push(read_explicit_source_path_metadata(
                    &label,
                    path_index,
                    library.library_id,
                    path.as_ref(),
                )?);
            }
        }

        Ok(Self {
            files,
            library_dependencies,
        })
    }

    /// Materializes source-file planning inputs from the stored metadata.
    pub fn source_file_inputs(&self) -> Vec<SourceFileUnitInput> {
        self.source_file_input_iter().collect()
    }

    /// Iterates source-file planning inputs without allocating a new vector.
    pub fn source_file_input_iter(&self) -> impl Iterator<Item = SourceFileUnitInput> + '_ {
        self.files
            .iter()
            .enumerate()
            .map(|(source_index, file)| SourceFileUnitInput {
                library_id: file.library_id,
                source_index,
                byte_len: file.byte_len,
                line_count: file.line_count.unwrap_or(0),
            })
    }

    /// Plans backend codegen units over path-backed source metadata.
    pub fn codegen_unit_plan(&self, limits: CodegenUnitLimits) -> CodegenUnitPlan {
        let mut units = Vec::new();
        CodegenUnitPlan::try_for_each_from_files(self.source_file_input_iter(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible path-manifest codegen-unit plan failed"));
        CodegenUnitPlan { units }
    }

    /// Plans frontend library-interface units over path-backed source metadata.
    pub fn frontend_unit_plan(&self, limits: CodegenUnitLimits) -> FrontendUnitPlan {
        let mut units = Vec::new();
        FrontendUnitPlan::try_for_each_from_files(self.source_file_input_iter(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible path-manifest frontend-unit plan failed"));
        FrontendUnitPlan { units }
    }

    /// Builds the full source-pack job graph from path-backed source metadata.
    pub fn job_plan(&self, limits: CodegenUnitLimits) -> SourcePackJobPlan {
        SourcePackJobPlan::from_file_stream_with_dependencies(
            self.source_file_input_iter(),
            &self.library_dependencies,
            limits,
        )
    }

    /// Produces a topological job schedule for the path-backed job graph.
    pub fn job_schedule(&self, limits: CodegenUnitLimits) -> SourcePackJobSchedule {
        self.job_plan(limits).job_schedule()
    }

    /// Produces a path-backed schedule that keeps frontend jobs bounded by limits.
    pub fn bounded_frontend_job_schedule(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackJobSchedule {
        self.job_plan(limits).bounded_frontend_job_schedule()
    }

    /// Builds the default bounded-frontend artifact plan.
    pub fn build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.bounded_frontend_build_plan(limits)
    }

    /// Builds an artifact plan with one frontend job per whole library.
    pub fn whole_library_frontend_build_plan(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackBuildPlan {
        self.job_plan(limits).build_plan()
    }

    /// Builds an artifact plan whose frontend and codegen work respect limits.
    pub fn bounded_frontend_build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.job_plan(limits).bounded_frontend_build_plan()
    }

    /// Builds a compact generic-target artifact manifest for this path manifest.
    pub fn compact_build_artifact_manifest(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            limits,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    /// Builds a compact artifact manifest for a concrete target.
    pub fn compact_build_artifact_manifest_for_target(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        let plan = self.job_plan(limits);
        let schedule = plan.bounded_frontend_job_schedule();
        plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    /// Returns the persisted library partition index for a concrete target.
    pub fn library_partition_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackLibraryPartitionIndex, CompileError> {
        Ok(library_partition_plan(self, target)?.index)
    }

    /// Returns the source-file metadata covered by a job.
    pub fn source_files_for_job(&self, job: &SourcePackJob) -> &[ExplicitSourcePathFile] {
        &self.files[job.source_range()]
    }

    /// Returns the source-file metadata covered by an artifact plan entry.
    pub fn source_files_for_artifact(
        &self,
        artifact: &SourcePackArtifactPlan,
    ) -> &[ExplicitSourcePathFile] {
        &self.files[artifact.source_range()]
    }

    /// Loads source strings for a job from the paths recorded in the manifest.
    pub fn load_sources_for_job(&self, job: &SourcePackJob) -> Result<Vec<String>, CompileError> {
        read_explicit_source_path_files("source-pack job", self.source_files_for_job(job))
    }

    /// Executes the default bounded-frontend path-backed build plan.
    pub fn execute_build_plan<E>(
        &self,
        limits: CodegenUnitLimits,
        executor: &mut E,
    ) -> Result<
        BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: PathBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_path_build(
            self,
            &build_plan,
            SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
            executor,
        )
    }

    /// Executes the path-backed build plan with explicit batch limits.
    pub fn execute_build_plan_with_batch_limits<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<
        BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: PathBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_path_build(self, &build_plan, batch_limits, executor)
    }

    /// Executes the path-backed build plan while returning executor handles.
    pub fn execute_build_plan_with_handles<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<HandleBuildExecutionResult<E::LinkedOutput>, CompileError>
    where
        E: PathHandleBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_path_handle_build(self, &build_plan, batch_limits, executor)
    }

    /// Executes path-backed artifact batches and batched link work with handles.
    pub fn execute_build_plan_with_batched_link_handles<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<HandleBuildExecutionResult<E::LinkedOutput>, CompileError>
    where
        E: PathHandleBatchedLinkBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_path_batched_link_build(self, &build_plan, batch_limits, executor)
    }

    /// Executes a path-backed build through an external artifact store.
    pub fn execute_build_plan_with_artifact_store<E, S>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
        store: &mut S,
    ) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
    where
        E: ArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: ArtifactStore,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_build_plan_with_store(self, &build_plan, batch_limits, executor, store)
    }
}

/// Validates library entries and returns topologically ordered ids plus edges.
pub(in crate::compiler) fn validate_explicit_source_library_entries(
    libraries: &[ExplicitSourceLibraryManifestEntry],
) -> Result<(Vec<u32>, Vec<SourcePackLibraryDependency>), CompileError> {
    if libraries.is_empty() {
        return Err(CompileError::GpuFrontend(
            "explicit source pack has no source files".to_string(),
        ));
    }

    let mut library_id_order = Vec::with_capacity(libraries.len());
    let mut library_id_set = BTreeSet::new();
    let mut library_dependencies = Vec::new();
    let mut seen_dependencies = BTreeSet::new();

    for library in libraries {
        if library.source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} has no source files",
                library.library_id
            )));
        }
        if !library_id_set.insert(library.library_id) {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} appears more than once",
                library.library_id
            )));
        }
        library_id_order.push(library.library_id);
    }

    for library in libraries {
        for &dependency_library_id in &library.dependency_library_ids {
            if dependency_library_id == library.library_id {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on itself",
                    library.library_id
                )));
            }
            if !library_id_set.contains(&dependency_library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on missing library {}",
                    library.library_id, dependency_library_id
                )));
            }
            if !seen_dependencies.insert((library.library_id, dependency_library_id)) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack duplicate library dependency {} -> {}",
                    library.library_id, dependency_library_id
                )));
            }
            library_dependencies.push(SourcePackLibraryDependency {
                library_id: library.library_id,
                depends_on_library_id: dependency_library_id,
            });
        }
    }

    let topological_library_ids =
        topologically_order_library_ids(&library_id_order, &library_dependencies)?;
    Ok((topological_library_ids, library_dependencies))
}

/// Converts vector path inputs into path streams without reordering libraries.
pub(in crate::compiler) fn path_streams_from_library_paths<I, P>(
    libraries: I,
) -> impl Iterator<Item = ExplicitSourceLibraryPathStream<Vec<P>>>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
{
    libraries
        .into_iter()
        .map(|library| ExplicitSourceLibraryPathStream {
            library_id: library.library_id,
            source_file_count: library.paths.len(),
            paths: library.paths,
            dependency_library_ids: library.dependency_library_ids,
        })
}

/// Converts path streams into dependency streams with sorted dependency ids.
pub(in crate::compiler) fn dependency_streams_from_path_streams<I, PI>(
    libraries: I,
) -> impl Iterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, Vec<u32>>>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
{
    libraries.into_iter().map(|library| {
        let mut dependency_library_ids = library.dependency_library_ids;
        dependency_library_ids.sort_unstable();
        ExplicitSourceLibraryPathDependencyStream {
            library_id: library.library_id,
            source_file_count: library.source_file_count,
            paths: library.paths,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        }
    })
}

/// Converts vector path inputs directly into dependency streams.
pub(in crate::compiler) fn dependency_streams_from_library_paths<I, P>(
    libraries: I,
) -> impl Iterator<Item = ExplicitSourceLibraryPathDependencyStream<Vec<P>, Vec<u32>>>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
{
    dependency_streams_from_path_streams(path_streams_from_library_paths(libraries))
}

/// Validates and orders path-backed libraries by dependency topology.
pub(in crate::compiler) fn ordered_dependency_streams_from_library_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<
    impl Iterator<Item = ExplicitSourceLibraryPathDependencyStream<Vec<P>, Vec<u32>>>,
    CompileError,
> {
    let library_entries = libraries
        .iter()
        .map(|library| ExplicitSourceLibraryManifestEntry {
            library_id: library.library_id,
            source_file_count: library.paths.len(),
            dependency_library_ids: library.dependency_library_ids.clone(),
        })
        .collect::<Vec<_>>();
    let (topological_library_ids, library_dependencies) =
        validate_explicit_source_library_entries(&library_entries)?;
    let mut dependencies_by_library = BTreeMap::<u32, BTreeSet<u32>>::new();
    for dependency in library_dependencies {
        dependencies_by_library
            .entry(dependency.library_id)
            .or_default()
            .insert(dependency.depends_on_library_id);
    }
    let mut remaining_libraries = libraries.into_iter().map(Some).collect::<Vec<_>>();
    Ok(topological_library_ids.into_iter().map(move |library_id| {
        let library_index = remaining_libraries
            .iter()
            .position(|library| {
                library
                    .as_ref()
                    .is_some_and(|library| library.library_id == library_id)
            })
            .expect("topological library id must come from explicit source library input");
        let library = remaining_libraries[library_index]
            .take()
            .expect("topological library should be unconsumed");
        let dependency_library_ids = dependencies_by_library
            .remove(&library.library_id)
            .map(|dependencies| dependencies.into_iter().collect::<Vec<_>>())
            .unwrap_or_default();
        ExplicitSourceLibraryPathDependencyStream {
            library_id: library.library_id,
            source_file_count: library.paths.len(),
            paths: library.paths,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        }
    }))
}

/// Returns library ids in first-seen source order.
pub(in crate::compiler) fn first_seen_library_ids(library_ids: &[u32]) -> Vec<u32> {
    let mut unique_ids = Vec::new();
    let mut seen_ids = BTreeSet::new();
    for &library_id in library_ids {
        if seen_ids.insert(library_id) {
            unique_ids.push(library_id);
        }
    }
    unique_ids
}

/// Orders library ids so dependencies are emitted before dependents.
pub(in crate::compiler) fn topologically_order_library_ids(
    library_ids: &[u32],
    library_dependencies: &[SourcePackLibraryDependency],
) -> Result<Vec<u32>, CompileError> {
    let mut library_index_by_id = BTreeMap::new();
    for (index, &library_id) in library_ids.iter().enumerate() {
        library_index_by_id.entry(library_id).or_insert(index);
    }
    let mut remaining_dependency_counts = vec![0usize; library_ids.len()];
    let mut dependents_by_library_index = vec![Vec::new(); library_ids.len()];
    let mut dependency_edges = BTreeSet::new();

    for dependency in library_dependencies {
        let Some(&library_index) = library_index_by_id.get(&dependency.library_id) else {
            continue;
        };
        let Some(&dependency_index) = library_index_by_id.get(&dependency.depends_on_library_id)
        else {
            remaining_dependency_counts[library_index] =
                remaining_dependency_counts[library_index].saturating_add(1);
            continue;
        };
        if dependency_edges.insert((library_index, dependency_index)) {
            remaining_dependency_counts[library_index] =
                remaining_dependency_counts[library_index].saturating_add(1);
            dependents_by_library_index[dependency_index].push(library_index);
        }
    }

    let mut sorted_ids = Vec::with_capacity(library_ids.len());
    let mut emitted = vec![false; library_ids.len()];
    let mut ready_indices = remaining_dependency_counts
        .iter()
        .enumerate()
        .filter_map(|(index, &count)| (count == 0).then_some(index))
        .collect::<BTreeSet<_>>();

    while let Some(index) = ready_indices.iter().next().copied() {
        ready_indices.remove(&index);
        if emitted[index] {
            continue;
        }
        emitted[index] = true;
        sorted_ids.push(library_ids[index]);

        for &dependent_index in &dependents_by_library_index[index] {
            let Some(remaining_dependencies) = remaining_dependency_counts.get_mut(dependent_index)
            else {
                continue;
            };
            if *remaining_dependencies == 0 {
                continue;
            }
            *remaining_dependencies -= 1;
            if *remaining_dependencies == 0 && !emitted[dependent_index] {
                ready_indices.insert(dependent_index);
            }
        }
    }

    if sorted_ids.len() != library_ids.len() {
        return Err(CompileError::GpuFrontend(
            "explicit source pack library dependencies contain a cycle".to_string(),
        ));
    }

    Ok(sorted_ids)
}
