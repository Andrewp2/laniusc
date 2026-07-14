use super::{
    super::{
        RecordedX86ArtifactMode,
        RecordedX86Codegen,
        support::{PooledReadbackBuffer, PooledStorageBuffer, RetainedX86Buffer},
    },
    timing::HostTimer,
};

/// Buffers and bind groups retained after x86 recording until output readback finishes.
pub(super) struct RetainedRecording {
    output_capacity: usize,
    artifact_mode: RecordedX86ArtifactMode,
    output_status_offset: u64,
    retained_buffers: Vec<RetainedX86Buffer>,
    retained_bind_groups: Vec<wgpu::BindGroup>,
    out_buf: PooledStorageBuffer,
    output_readback: PooledReadbackBuffer,
    object_metadata_readback: PooledReadbackBuffer,
    object_reloc_kind: RetainedX86Buffer,
    object_reloc_site_offset: RetainedX86Buffer,
    object_reloc_target_offset: RetainedX86Buffer,
    object_symbol_record: RetainedX86Buffer,
    status_trace_readback: Option<wgpu::Buffer>,
}

impl RetainedRecording {
    /// Creates a retained recording bundle from output and lifetime-owned resources.
    pub(super) fn new(
        output_capacity: usize,
        artifact_mode: RecordedX86ArtifactMode,
        output_status_offset: u64,
        retained_buffers: Vec<RetainedX86Buffer>,
        retained_bind_groups: Vec<wgpu::BindGroup>,
        out_buf: PooledStorageBuffer,
        output_readback: PooledReadbackBuffer,
        object_metadata_readback: PooledReadbackBuffer,
        object_reloc_kind: RetainedX86Buffer,
        object_reloc_site_offset: RetainedX86Buffer,
        object_reloc_target_offset: RetainedX86Buffer,
        object_symbol_record: RetainedX86Buffer,
        status_trace_readback: Option<wgpu::Buffer>,
    ) -> Self {
        Self {
            output_capacity,
            artifact_mode,
            output_status_offset,
            retained_buffers,
            retained_bind_groups,
            out_buf,
            output_readback,
            object_metadata_readback,
            object_reloc_kind,
            object_reloc_site_offset,
            object_reloc_target_offset,
            object_symbol_record,
            status_trace_readback,
        }
    }

    /// Converts retained recording resources into the public recorded-codegen handle.
    pub(super) fn into_recorded(self, host_timer: &mut HostTimer) -> RecordedX86Codegen {
        host_timer.stamp("recorded_result_ready");
        RecordedX86Codegen {
            artifact_mode: self.artifact_mode,
            output_capacity: self.output_capacity,
            output_status_offset: self.output_status_offset,
            _retained_buffers: self.retained_buffers,
            _retained_bind_groups: self.retained_bind_groups,
            out_buf: self.out_buf,
            output_readback: self.output_readback,
            object_metadata_readback: self.object_metadata_readback,
            object_reloc_kind: self.object_reloc_kind,
            object_reloc_site_offset: self.object_reloc_site_offset,
            object_reloc_target_offset: self.object_reloc_target_offset,
            object_symbol_record: self.object_symbol_record,
            status_trace_readback: self.status_trace_readback,
        }
    }
}
