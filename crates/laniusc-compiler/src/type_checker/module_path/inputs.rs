use super::super::*;

/// Borrowed inputs used to build the resident module/path state.
///
/// The constructor groups parser HIR rows, name rows, type rows, call rows, and
/// optional scratch aliases here so module-path bind-group creation remains
/// explicit about every buffer identity it captures.
pub(in crate::type_checker) struct CreateInputs<'a> {
    pub(in crate::type_checker) params: &'a LaniusBuffer<TypeCheckParams>,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) source_file_capacity: u32,
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) hir_node_capacity: u32,
    pub(in crate::type_checker) hir_active_count_buf: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) hir_active_dispatch_args: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) hir_items: GpuTypeCheckHirItemBuffers<'a>,
    pub(in crate::type_checker) decl_name_token: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_id_by_name_token: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_kind: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) type_instance_arg_ref_tag: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) type_instance_arg_ref_payload: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) type_decl_generic_param_count_by_owner_token: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) module_record_family_bits: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) module_record_family_flag: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) module_record_prefix: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) module_record_scan_workspace:
        PrefixScanWorkspace<&'a LaniusBuffer<u32>>,
    pub(in crate::type_checker) module_value_scan_workspace:
        PrefixScanWorkspace<&'a LaniusBuffer<u32>>,
    pub(in crate::type_checker) decl_type_key_prefix: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_value_key_prefix: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_type_key_count_out: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_value_key_count_out: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) decl_status: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_type_count: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_value_count: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_type_prefix: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_value_prefix: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_type_count_out: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) import_visible_value_count_out: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) dependency_interfaces: Option<&'a GpuDependencyInterfaceState>,
}
