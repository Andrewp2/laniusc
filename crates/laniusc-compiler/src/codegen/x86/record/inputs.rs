use super::super::*;

/// Borrowed parser, type-check, feature, and scratch inputs for one x86 recording.
pub struct RecordElfInputs<'a, 'timer> {
    pub source_len: u32,
    pub source_bytes_buf: &'a wgpu::Buffer,
    pub token_capacity: u32,
    pub n_hir_nodes: u32,
    pub inst_hir_node_count: u32,
    pub hir_status_buf: &'a wgpu::Buffer,
    pub active_hir_dispatch_args_buf: &'a wgpu::Buffer,
    pub hir_kind_buf: &'a wgpu::Buffer,
    pub hir_item_kind_buf: &'a wgpu::Buffer,
    pub parent_buf: &'a wgpu::Buffer,
    pub subtree_end_buf: &'a wgpu::Buffer,
    pub function_metadata: GpuX86FunctionMetadataBuffers<'a>,
    pub expr_metadata: GpuX86ExprMetadataBuffers<'a>,
    pub call_metadata: GpuX86CallMetadataBuffers<'a>,
    pub array_metadata: GpuX86ArrayMetadataBuffers<'a>,
    pub enum_metadata: GpuX86EnumMetadataBuffers<'a>,
    pub struct_metadata: GpuX86StructMetadataBuffers<'a>,
    pub type_metadata: GpuX86TypeMetadataBuffers<'a>,
    pub visible_decl_buf: &'a wgpu::Buffer,
    pub fn_entrypoint_tag_buf: &'a wgpu::Buffer,
    pub feature_summary: X86FeatureSummary,
    pub external_scratch: GpuX86ExternalScratchBuffers<'a>,
    pub timer: Option<&'timer mut crate::gpu::timer::GpuTimer>,
}
