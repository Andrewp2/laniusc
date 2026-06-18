use super::super::support::UniformBindingArray;

/// Byte and dynamic offsets for rows in an indirect-dispatch uniform array.
pub(super) struct IndirectUniformOffsets {
    pub(super) indirect: Vec<u64>,
    pub(super) dynamic: Vec<u32>,
}

impl IndirectUniformOffsets {
    /// Computes one indirect-argument offset and one dynamic uniform offset per parameter row.
    pub(super) fn for_params(params: &UniformBindingArray) -> Self {
        Self {
            indirect: (0..params.len())
                .map(|step_i| (step_i * 3 * std::mem::size_of::<u32>()) as u64)
                .collect(),
            dynamic: (0..params.len())
                .map(|step_i| params.dynamic_offset(step_i))
                .collect(),
        }
    }
}
