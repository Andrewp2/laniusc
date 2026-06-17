use super::{
    super::{
        RecordedX86Codegen,
        support::{PooledReadbackBuffer, PooledStorageBuffer, RetainedX86Buffer},
    },
    timing::HostTimer,
};

pub(super) struct RetainedRecording {
    output_capacity: usize,
    output_status_offset: u64,
    retained_buffers: Vec<RetainedX86Buffer>,
    retained_bind_groups: Vec<wgpu::BindGroup>,
    out_buf: PooledStorageBuffer,
    output_readback: PooledReadbackBuffer,
    status_trace_readback: Option<wgpu::Buffer>,
}

impl RetainedRecording {
    pub(super) fn new(
        output_capacity: usize,
        output_status_offset: u64,
        retained_buffers: Vec<RetainedX86Buffer>,
        retained_bind_groups: Vec<wgpu::BindGroup>,
        out_buf: PooledStorageBuffer,
        output_readback: PooledReadbackBuffer,
        status_trace_readback: Option<wgpu::Buffer>,
    ) -> Self {
        Self {
            output_capacity,
            output_status_offset,
            retained_buffers,
            retained_bind_groups,
            out_buf,
            output_readback,
            status_trace_readback,
        }
    }

    pub(super) fn into_recorded(self, host_timer: &mut HostTimer) -> RecordedX86Codegen {
        host_timer.stamp("recorded_result_ready");
        RecordedX86Codegen {
            output_capacity: self.output_capacity,
            output_status_offset: self.output_status_offset,
            _retained_buffers: self.retained_buffers,
            _retained_bind_groups: self.retained_bind_groups,
            out_buf: self.out_buf,
            output_readback: self.output_readback,
            status_trace_readback: self.status_trace_readback,
        }
    }
}
