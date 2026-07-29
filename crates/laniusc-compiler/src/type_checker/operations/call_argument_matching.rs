use super::super::*;

/// Compiled GPU operation that relates every compact call-argument row to its
/// parameter row and emits the resulting generic and const-generic claims.
///
/// The two kernels and their reflected bindings form one semantic operation.
/// Recorders supply only the active row capacity; they cannot execute a
/// partial call-matching schedule or pair a kernel with the wrong bind group.
pub(in crate::type_checker) struct CallArgumentMatchingOperation {
    initialize: ComputeOperation,
    consume: ComputeOperation,
}

impl CallArgumentMatchingOperation {
    pub(in crate::type_checker) fn new(
        initialize: ComputeOperation,
        consume: ComputeOperation,
    ) -> Self {
        Self {
            initialize,
            consume,
        }
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.initialize.record(encoder)?;
        self.consume.record(encoder)
    }
}
