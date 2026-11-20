use super::{super::*, inputs::CreateInputs, layout::Layout};
use crate::gpu::operations::{
    CopyBufferOperation, StepProgramOperation, step_program_group_counts, step_program_group_variant,
};

pub(in crate::type_checker) const MODULE_PROGRAM_SLOTS: usize = 2;

pub(in crate::type_checker) struct ModuleProgram {
    programs: [StepProgramOperation; 2],
    failure: CopyBufferOperation,
}

impl ModuleProgram {
    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        rows: u32,
    ) -> Result<()> {
        self.programs[step_program_group_variant(u64::from(rows))].record(encoder)?;
        self.failure.record(encoder);
        Ok(())
    }
}

pub(in crate::type_checker) struct ModulePrograms {
    pub(in crate::type_checker) build_paths: ModuleProgram,
    pub(in crate::type_checker) compact_records: ModuleProgram,
}

pub(super) fn create_module_programs(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    resources: &ResourceMap<'_>,
) -> Result<ModulePrograms> {
    assert!(
        inputs.token_capacity <= 0x07ff_ffff,
        "path-prefix row capacity exceeds the round-tagged table encoding",
    );
    let sync = graph.u32_buffer("module_step_program_sync")?;
    let failure_buffer: LaniusBuffer<u32> =
        typed_buffer_from_resources(resources, "module_step_program_failed")?;
    let mut resources = resources.clone();
    resources.buffer("module_step_program_sync", &sync);
    resources.buffer("step_program_sync", &sync);
    resources.buffer("gParams", inputs.params);
    let [small, large] = step_program_group_counts();
    let make_program = |spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
                        failure_copy, slot, options| -> Result<_> {
        let build = |groups| {
            StepProgramOperation::new(
                device,
                graph,
                &resources,
                spec.name,
                passes.kernel(spec.kernel),
                &sync,
                slot,
                groups,
                options,
            )
        };
        Ok(ModuleProgram {
            programs: [build(small)?, build(large)?],
            failure: CopyBufferOperation::new(
                graph,
                failure_copy,
                "module_step_program_sync",
                &sync,
                StepProgramOperation::failed_offset(slot),
                "module_step_program_failed",
                &failure_buffer,
                u64::from(slot) * 4,
                4,
            )?,
        })
    };
    Ok(ModulePrograms {
        build_paths: make_program(BUILD_PATH_TABLES, PATH_PROGRAM_FAILURE_COPY, 0, 0)?,
        compact_records: make_program(
            COMPACT_RECORDS,
            RECORD_PROGRAM_FAILURE_COPY,
            1,
            layout.module_capacity_u32,
        )?,
    })
}
