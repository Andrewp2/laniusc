use super::*;

impl FilesystemArtifactStore {
    /// Loads and validates the hierarchical link plan index for a target.
    pub fn load_hierarchical_link_plan_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkPlanIndex, CompileError> {
        let path = self.hierarchical_link_plan_index_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack hierarchical link plan index")?;
        let index = parse_store_json::<SourcePackHierarchicalLinkPlanIndex>(
            &bytes,
            &path,
            "source-pack hierarchical link plan index",
        )?;
        validate_link_plan_index(&index, target)?;
        Ok(index)
    }

    /// Stores one compact hierarchical link group page.
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
        let bytes = serialize_store_json(
            &stored_group,
            format!(
                "source-pack hierarchical link group page {}",
                group.group_index
            ),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack hierarchical link group page")?;
        Ok(path)
    }

    /// Loads and validates one hierarchical link group page.
    pub fn load_hierarchical_link_group_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
        let path = self.hierarchical_link_group_page_path_for_target(target, group_index);
        let bytes = read_store_file(&path, "source-pack hierarchical link group page")?;
        let group = parse_store_json::<SourcePackHierarchicalLinkGroupPage>(
            &bytes,
            &path,
            "source-pack hierarchical link group page",
        )?;
        validate_link_group_page(&group, target, Some(group_index))?;
        Ok(group)
    }

    /// Loads and validates the hierarchical link execution index for a target.
    pub fn load_hierarchical_link_execution_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkExecutionIndex, CompileError> {
        let path = self.hierarchical_link_execution_index_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack hierarchical link execution index")?;
        let index = parse_store_json::<SourcePackHierarchicalLinkExecutionIndex>(
            &bytes,
            &path,
            "source-pack hierarchical link execution index",
        )?;
        validate_link_execution_index(&index, target)?;
        Ok(index)
    }

    /// Stores one compact hierarchical link execution page and sidecars.
    ///
    /// Inline interface, object, and partial-link inputs are split into bounded
    /// pages before the compact execution page is written.
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
        self.write_compact_hierarchical_link_execution_page(&stored_page)
    }

    /// Stores a compact execution page whose bounded sidecars were already
    /// emitted by the schedule-to-execution streaming writers.
    pub(in crate::compiler) fn store_prepared_hierarchical_link_execution_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_execution_page(page, page.target, Some(page.group_index))?;
        if !page.input_interfaces.is_empty()
            || !page.input_objects.is_empty()
            || !page.input_group_indices.is_empty()
            || !page.input_group_output_keys.is_empty()
        {
            return Err(library_partition_contract_error(format!(
                "prepared hierarchical link execution group {} still carries inline inputs",
                page.group_index
            )));
        }
        self.write_compact_hierarchical_link_execution_page(page)
    }

    fn write_compact_hierarchical_link_execution_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<PathBuf, CompileError> {
        let path =
            self.hierarchical_link_execution_page_path_for_target(page.target, page.group_index);
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack hierarchical link execution page {}",
                page.group_index
            ),
        )?;
        write_store_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution page",
        )?;
        Ok(path)
    }

    /// Splits interface artifact refs into hierarchical link sidecar pages.
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

    /// Splits codegen-object artifact refs into hierarchical link sidecar pages.
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

    /// Splits partial-link input groups into hierarchical link sidecar pages.
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

    /// Stores one hierarchical link interface-input sidecar page.
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
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack hierarchical link execution interface page {}:{}",
                page.group_index, page.page_index
            ),
        )?;
        write_store_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution interface page",
        )?;
        Ok(path)
    }

    /// Stores one hierarchical link object-input sidecar page.
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
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack hierarchical link execution object page {}:{}",
                page.group_index, page.page_index
            ),
        )?;
        write_store_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution object page",
        )?;
        Ok(path)
    }

    /// Stores one hierarchical link partial-input sidecar page.
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
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack hierarchical link execution partial page {}:{}",
                page.group_index, page.page_index
            ),
        )?;
        write_store_file_atomic(
            &path,
            &bytes,
            "source-pack hierarchical link execution partial page",
        )?;
        Ok(path)
    }

    /// Loads and validates one compact hierarchical link execution page.
    pub fn load_hierarchical_link_execution_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
        let path = self.hierarchical_link_execution_page_path_for_target(target, group_index);
        let bytes = read_store_file(&path, "source-pack hierarchical link execution page")?;
        let page = parse_store_json::<SourcePackHierarchicalLinkExecutionPage>(
            &bytes,
            &path,
            "source-pack hierarchical link execution page",
        )?;
        validate_link_execution_page(&page, target, Some(group_index))?;
        Ok(page)
    }

    /// Loads and validates one hierarchical link interface-input sidecar page.
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
        let bytes = read_store_file(
            &path,
            "source-pack hierarchical link execution interface page",
        )?;
        let page = parse_store_json::<SourcePackHierarchicalLinkExecutionInterfacePage>(
            &bytes,
            &path,
            "source-pack hierarchical link execution interface page",
        )?;
        validate_link_execution_interface_page(&page, target, group_index, page_index)?;
        Ok(page)
    }

    /// Loads and validates one hierarchical link object-input sidecar page.
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
        let bytes = read_store_file(&path, "source-pack hierarchical link execution object page")?;
        let page = parse_store_json::<SourcePackHierarchicalLinkExecutionObjectPage>(
            &bytes,
            &path,
            "source-pack hierarchical link execution object page",
        )?;
        validate_link_execution_object_page(&page, target, group_index, page_index)?;
        Ok(page)
    }

    /// Loads and validates one hierarchical link partial-input sidecar page.
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
        let bytes = read_store_file(
            &path,
            "source-pack hierarchical link execution partial page",
        )?;
        let page = parse_store_json::<SourcePackHierarchicalLinkExecutionPartialPage>(
            &bytes,
            &path,
            "source-pack hierarchical link execution partial page",
        )?;
        validate_link_execution_partial_page(&page, target, group_index, page_index)?;
        Ok(page)
    }
}
