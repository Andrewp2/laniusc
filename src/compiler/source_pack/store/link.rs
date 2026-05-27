use super::*;

impl FilesystemArtifactStore {
    pub fn load_hierarchical_link_plan_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkPlanIndex, CompileError> {
        let path = self.hierarchical_link_plan_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link plan index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackHierarchicalLinkPlanIndex>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link plan index {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_link_plan_index(&index, target)?;
        Ok(index)
    }

    pub fn store_hierarchical_link_group_page(
        &self,
        group: &SourcePackHierarchicalLinkGroupPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_group_page(group, group.target, Some(group.group_index))?;
        let mut stored_group = group.clone();
        stored_group.input_frontend_job_count =
            hierarchical_link_group_input_frontend_job_count(group);
        stored_group.input_frontend_job_indices.clear();
        if stored_group.kind == SourcePackHierarchicalLinkGroupKind::Reduce {
            stored_group.input_partition_count =
                hierarchical_link_group_input_partition_count(group);
            stored_group.input_partition_indices.clear();
        }
        validate_link_group_page(&stored_group, group.target, Some(group.group_index))?;
        let path =
            self.hierarchical_link_group_page_path_for_target(group.target, group.group_index);
        let bytes = serde_json::to_vec_pretty(&stored_group).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link group page {}: {err}",
                group.group_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack hierarchical link group page")?;
        Ok(path)
    }

    pub fn load_hierarchical_link_group_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
        let path = self.hierarchical_link_group_page_path_for_target(target, group_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link group page {}: {err}",
                path.display()
            ))
        })?;
        let group = serde_json::from_slice::<SourcePackHierarchicalLinkGroupPage>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link group page {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_link_group_page(&group, target, Some(group_index))?;
        Ok(group)
    }

    pub fn load_hierarchical_link_execution_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkExecutionIndex, CompileError> {
        let path = self.hierarchical_link_execution_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionIndex>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution index {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_execution_index(&index, target)?;
        Ok(index)
    }

    pub fn store_hierarchical_link_execution_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_execution_page_store_input(page, page.target, Some(page.group_index))?;
        let explicit_input_interface_page_count = if page.input_interfaces.is_empty() {
            page.input_interface_page_count
        } else {
            self.store_link_interface_pages_from_refs(
                page.target,
                page.group_index,
                page.job_index,
                &page.input_interfaces,
            )?
        };
        let input_interface_count =
            page.input_interfaces
                .len()
                .saturating_add(job_index_range_dependency_count(
                    &page.input_interface_ranges,
                ));
        let input_interface_count = if page.input_interfaces.is_empty() {
            page.input_interface_count
        } else {
            input_interface_count
        };
        let input_object_page_count = if page.input_objects.is_empty() {
            page.input_object_page_count
        } else {
            self.store_link_object_pages_from_refs(
                page.target,
                page.group_index,
                page.job_index,
                &page.input_objects,
            )?
        };
        let input_object_count = if page.input_objects.is_empty() {
            page.input_object_count
        } else {
            page.input_objects.len()
        };
        let input_group_page_count =
            if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
                page.input_group_page_count
            } else {
                self.store_partial_link_pages_from_inputs(
                    page.target,
                    page.group_index,
                    page.job_index,
                    &page.input_group_indices,
                    &page.input_group_output_keys,
                )?
            };
        let input_group_count =
            if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
                page.input_group_count
            } else {
                page.input_group_indices.len()
            };
        let mut stored_page = page.clone();
        stored_page.input_interface_count = input_interface_count;
        stored_page.input_interface_page_count = explicit_input_interface_page_count;
        stored_page.input_interfaces.clear();
        stored_page.input_object_count = input_object_count;
        stored_page.input_object_page_count = input_object_page_count;
        stored_page.input_objects.clear();
        stored_page.input_group_count = input_group_count;
        stored_page.input_group_page_count = input_group_page_count;
        stored_page.input_group_indices.clear();
        stored_page.input_group_output_keys.clear();
        validate_link_execution_page(&stored_page, page.target, Some(page.group_index))?;
        let path =
            self.hierarchical_link_execution_page_path_for_target(page.target, page.group_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution page {}: {err}",
                page.group_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution page",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_link_interface_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_interfaces: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_interfaces) in input_interfaces
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackHierarchicalLinkExecutionInterfacePage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position: page_index.saturating_mul(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                ),
                input_count: input_interfaces.len(),
                input_interfaces: input_interfaces.to_vec(),
            };
            self.store_hierarchical_link_execution_interface_page(&page)?;
        }
        Ok(input_interfaces
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn store_link_object_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_objects: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_objects) in input_objects
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position: page_index.saturating_mul(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
                ),
                input_count: input_objects.len(),
                input_objects: input_objects.to_vec(),
            };
            self.store_hierarchical_link_execution_object_page(&page)?;
        }
        Ok(input_objects
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn store_partial_link_pages_from_inputs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_group_indices: &[usize],
        input_group_output_keys: &[String],
    ) -> Result<usize, CompileError> {
        for (page_index, input_group_indices) in input_group_indices
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let first_input_position = page_index
                .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
            let input_group_output_keys = input_group_output_keys[first_input_position
                ..first_input_position.saturating_add(input_group_indices.len())]
                .to_vec();
            let page = SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position,
                input_count: input_group_indices.len(),
                input_group_indices: input_group_indices.to_vec(),
                input_group_output_keys,
            };
            self.store_hierarchical_link_execution_partial_page(&page)?;
        }
        Ok(input_group_indices
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE))
    }

    pub fn store_hierarchical_link_execution_interface_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionInterfacePage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_execution_interface_page(
            page,
            page.target,
            page.group_index,
            page.page_index,
        )?;
        let path = self.hierarchical_link_execution_interface_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution interface page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution interface page",
        )?;
        Ok(path)
    }

    pub fn store_hierarchical_link_execution_object_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionObjectPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_execution_object_page(page, page.target, page.group_index, page.page_index)?;
        let path = self.hierarchical_link_execution_object_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution object page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution object page",
        )?;
        Ok(path)
    }

    pub fn store_hierarchical_link_execution_partial_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPartialPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_execution_partial_page(page, page.target, page.group_index, page.page_index)?;
        let path = self.hierarchical_link_execution_partial_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution partial page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution partial page",
        )?;
        Ok(path)
    }

    pub fn load_hierarchical_link_execution_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
        let path = self.hierarchical_link_execution_page_path_for_target(target, group_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution page {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_execution_page(&page, target, Some(group_index))?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_interface_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionInterfacePage, CompileError> {
        let path = self.hierarchical_link_execution_interface_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution interface page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackHierarchicalLinkExecutionInterfacePage>(&bytes)
                .map_err(|err| {
                    CompileError::GpuFrontend(format!(
                        "parse source-pack hierarchical link execution interface page {}: {err}",
                        path.display()
                    ))
                })?;
        validate_link_execution_interface_page(&page, target, group_index, page_index)?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_object_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionObjectPage, CompileError> {
        let path = self.hierarchical_link_execution_object_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution object page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionObjectPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution object page {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_execution_object_page(&page, target, group_index, page_index)?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_partial_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPartialPage, CompileError> {
        let path = self.hierarchical_link_execution_partial_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution partial page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionPartialPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution partial page {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_execution_partial_page(&page, target, group_index, page_index)?;
        Ok(page)
    }
}
