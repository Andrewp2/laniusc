use super::*;

#[derive(Default)]
pub(super) struct RecordingSourcePackByteArtifactExecutor {
    pub(super) events: Vec<String>,
    pub(super) fail_library_interface_calls: usize,
    pub(super) record_paged_dependency_batches: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct TestByteLinkHandle {
    interface_count: usize,
    object_count: usize,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct TestByteBuildHandle {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_files_len: usize,
    dependency_count: usize,
}

fn test_partial_link_counts(partial: &[u8]) -> Result<(usize, usize), CompileError> {
    let text = std::str::from_utf8(partial).map_err(|err| {
        CompileError::GpuFrontend(format!("test partial link artifact was not utf8: {err}"))
    })?;
    let parts = text.split(':').collect::<Vec<_>>();
    if parts.len() != 4 || parts[0] != "partial" {
        return Err(CompileError::GpuFrontend(format!(
            "test partial link artifact has invalid shape {text:?}"
        )));
    }
    let interface_count = parts[2].parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "test partial link interface count {:?} is invalid: {err}",
            parts[2]
        ))
    })?;
    let object_count = parts[3].parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "test partial link object count {:?} is invalid: {err}",
            parts[3]
        ))
    })?;
    Ok((interface_count, object_count))
}

impl ArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = Vec<u8>;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        if self.fail_library_interface_calls > 0 {
            self.fail_library_interface_calls -= 1;
            self.events.push(format!(
                "fail-frontend:{}:{}:{}",
                job.library_id,
                source_files.len(),
                dependency_interfaces.len()
            ));
            return Err(CompileError::GpuFrontend(format!(
                "test injected frontend failure for job {}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "frontend:{}:{}:{}",
            job.library_id,
            source_files.len(),
            dependency_interfaces.len()
        ));
        Ok(format!(
            "iface:{}:{}:{}",
            job.library_id,
            source_files.len(),
            dependency_interfaces.len()
        )
        .into_bytes())
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let expected_interface_prefix = format!("iface:{}:", job.library_id);
        let interface = std::str::from_utf8(library_interface).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "test library interface artifact was not utf8: {err}"
            ))
        })?;
        if !interface.starts_with(&expected_interface_prefix) {
            return Err(CompileError::GpuFrontend(format!(
                "codegen job {} received wrong owning interface artifact {interface:?}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            job.library_id,
            job.source_range(),
            source_files.len(),
            dependency_interfaces.len()
        ));
        Ok(format!(
            "obj:{}:{}-{}:{}",
            job.library_id,
            job.first_source_index,
            job.first_source_index + job.source_file_count,
            dependency_interfaces.len()
        )
        .into_bytes())
    }

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!("begin-link:{}", job.job_index));
        Ok(TestByteLinkHandle::default())
    }

    fn link_library_interface_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-interfaces:{}:{}",
            batch.batch_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_codegen_object_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-objects:{}:{}",
            batch.batch_index,
            codegen_objects.len()
        ));
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-link:{}:{}:{}",
            job.job_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "linked:{}:{}",
            link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }
}

impl PagedArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<Self::LibraryInterfaceBuildHandle, CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "begin-frontend:{}:{}",
                job.library_id,
                source_files.len()
            ));
        }
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_library_interface_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "frontend-deps:{}:{}",
                job.library_id,
                dependency_interfaces.len()
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_library_interface(
        &mut self,
        job: &SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        if self.fail_library_interface_calls > 0 {
            self.fail_library_interface_calls -= 1;
            self.events.push(format!(
                "fail-frontend:{}:{}:{}",
                handle.library_id, handle.source_files_len, handle.dependency_count
            ));
            return Err(CompileError::GpuFrontend(format!(
                "test injected frontend failure for job {}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "frontend:{}:{}:{}",
            handle.library_id, handle.source_files_len, handle.dependency_count
        ));
        Ok(format!(
            "iface:{}:{}:{}",
            handle.library_id, handle.source_files_len, handle.dependency_count
        )
        .into_bytes())
    }

    fn begin_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
    ) -> Result<Self::CodegenObjectBuildHandle, CompileError> {
        let expected_interface_prefix = format!("iface:{}:", job.library_id);
        let interface = std::str::from_utf8(library_interface).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "test library interface artifact was not utf8: {err}"
            ))
        })?;
        if !interface.starts_with(&expected_interface_prefix) {
            return Err(CompileError::GpuFrontend(format!(
                "codegen job {} received wrong owning interface artifact {interface:?}",
                job.job_index
            )));
        }
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "begin-codegen:{}:{}",
                job.library_id,
                source_files.len()
            ));
        }
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_codegen_object_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "codegen-deps:{}:{}",
                job.library_id,
                dependency_interfaces.len()
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_codegen_object(
        &mut self,
        _job: &SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let source_end = handle
            .first_source_index
            .saturating_add(handle.source_file_count);
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            handle.library_id,
            handle.first_source_index..source_end,
            handle.source_files_len,
            handle.dependency_count
        ));
        Ok(format!(
            "obj:{}:{}-{}:{}",
            handle.library_id, handle.first_source_index, source_end, handle.dependency_count
        )
        .into_bytes())
    }
}

impl AsyncPagedArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = Vec<u8>;
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::begin_library_interface(self, job, source_files)
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::add_library_interface_dependency_batch(
                self,
                job,
                handle,
                dependency_interfaces,
            )
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::finish_library_interface(self, job, handle)
        })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::begin_codegen_object(
                self,
                job,
                source_files,
                library_interface,
            )
        })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::add_codegen_object_dependency_batch(
                self,
                job,
                handle,
                dependency_interfaces,
            )
        })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move {
            <Self as PagedArtifactBuildExecutor>::finish_codegen_object(self, job, handle)
        })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(
            async move { <Self as ArtifactBuildExecutor>::begin_link_codegen_objects(self, job) },
        )
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as ArtifactBuildExecutor>::link_library_interface_batch(
                self,
                job,
                link_handle,
                batch,
                library_interfaces,
            )
        })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as ArtifactBuildExecutor>::link_codegen_object_batch(
                self,
                job,
                link_handle,
                batch,
                codegen_objects,
            )
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move {
            <Self as ArtifactBuildExecutor>::finish_link_codegen_objects(self, job, link_handle)
        })
    }
}

impl HierarchicalLinkExecutor for RecordingSourcePackByteArtifactExecutor {
    type PartialLinkArtifact = Vec<u8>;

    fn begin_hierarchical_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!(
            "begin-hlink:{}:{}",
            page.group_index, page.job_index
        ));
        Ok(TestByteLinkHandle::default())
    }

    fn link_hierarchical_library_interfaces(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-interfaces:{}:{}",
            page.group_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_hierarchical_codegen_objects(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-objects:{}:{}",
            page.group_index,
            codegen_objects.len()
        ));
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn link_hierarchical_partial_links(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        partial_links: &[Self::PartialLinkArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-partials:{}:{}",
            page.group_index,
            partial_links.len()
        ));
        for partial in partial_links {
            let (interface_count, object_count) = test_partial_link_counts(partial)?;
            link_handle.interface_count += interface_count;
            link_handle.object_count += object_count;
        }
        Ok(())
    }

    fn finish_hierarchical_partial_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        self.events.push(format!(
            "finish-hpartial:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "partial:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }

    fn finish_hierarchical_link_output(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-hlink:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "hlinked:{}:{}",
            link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }
}
