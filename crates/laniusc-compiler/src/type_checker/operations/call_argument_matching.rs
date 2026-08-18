use super::super::*;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum CallArgumentMatchStage {
    Direct,
    ModuleValues,
    MethodResults,
    MethodModules,
    Final,
}

impl CallArgumentMatchStage {
    pub(in crate::type_checker) const fn operation_names(
        self,
    ) -> (&'static str, &'static str, &'static str) {
        match self {
            Self::Direct => (
                CALLS_ARGUMENT_MATCH_INITIALIZE.name,
                CALLS_ARGUMENT_MATCH_CONSUME.name,
                CALLS_APPLY_ARGUMENTS.name,
            ),
            Self::ModuleValues => (
                CALLS_ARGUMENT_MATCH_MODULE_INITIALIZE.name,
                CALLS_ARGUMENT_MATCH_MODULE_CONSUME.name,
                CALLS_APPLY_MODULE_ARGUMENTS.name,
            ),
            Self::MethodResults => (
                CALLS_ARGUMENT_MATCH_METHOD_RESULT_INITIALIZE.name,
                CALLS_ARGUMENT_MATCH_METHOD_RESULT_CONSUME.name,
                CALLS_APPLY_METHOD_RESULT_ARGUMENTS.name,
            ),
            Self::MethodModules => (
                CALLS_ARGUMENT_MATCH_METHOD_MODULE_INITIALIZE.name,
                CALLS_ARGUMENT_MATCH_METHOD_MODULE_CONSUME.name,
                CALLS_APPLY_METHOD_MODULE_ARGUMENTS.name,
            ),
            Self::Final => (
                CALLS_ARGUMENT_MATCH_FINAL_INITIALIZE.name,
                CALLS_ARGUMENT_MATCH_FINAL_CONSUME.name,
                CALLS_APPLY_FINAL_ARGUMENTS.name,
            ),
        }
    }
}

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

    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: CallArgumentMatchStage,
    ) -> Result<()> {
        let (initialize, consume, _) = stage.operation_names();
        self.initialize.record_as(encoder, initialize)?;
        self.consume.record_as(encoder, consume)
    }
}
