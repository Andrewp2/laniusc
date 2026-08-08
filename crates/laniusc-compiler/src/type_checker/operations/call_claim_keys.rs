use super::super::*;

const KEY_FIELD_COUNT: u32 = 3;
const MAX_RADIX_STEPS: u32 = 12;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum CallClaimKind {
    Generic,
    Const,
}

impl CallClaimKind {
    fn definition(self) -> RadixSortDefinition {
        match self {
            Self::Generic => compiler_graph::GENERIC_CLAIM_RADIX_SORT,
            Self::Const => compiler_graph::CONST_CLAIM_RADIX_SORT,
        }
    }
}

fn radix_bytes(token_capacity: u32, claim_capacity: u32) -> u32 {
    match token_capacity
        .max(claim_capacity)
        .saturating_add(8193)
        .max(1)
    {
        0..=0xff => 1,
        0x100..=0xffff => 2,
        0x1_0000..=0xff_ffff => 3,
        _ => 4,
    }
}

fn radix_steps(bytes: u32) -> u32 {
    let steps = bytes * KEY_FIELD_COUNT;
    (steps + steps % 2).min(MAX_RADIX_STEPS)
}

pub(in crate::type_checker) fn call_claim_radix_steps(
    token_capacity: u32,
    claim_capacity: u32,
) -> u32 {
    radix_steps(radix_bytes(token_capacity, claim_capacity))
}

pub(in crate::type_checker) struct CallClaimKeyBuild<'a> {
    pub kind: CallClaimKind,
    pub token_capacity: u32,
    pub claim_capacity: u32,
    pub dispatch_args: &'a LaniusBuffer<u32>,
    pub resources: &'a ResourceMap<'a>,
}

pub(in crate::type_checker) struct CallClaimKeyPipeline {
    dispatch_pass: PassData,
    _dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    dispatch: wgpu::BindGroup,
    dispatch_args: LaniusBuffer<u32>,
    sort: RadixSortOperation<ModuleKeyRadixParams>,
}

impl CallClaimKeyPipeline {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        input: CallClaimKeyBuild<'_>,
    ) -> Result<Self> {
        let definition = input.kind.definition();
        let names = definition.resources;
        let bytes = radix_bytes(input.token_capacity, input.claim_capacity);
        let blocks = input.claim_capacity.div_ceil(256).max(1);
        let params = |key_step| ModuleKeyRadixParams {
            module_capacity: input.claim_capacity,
            reserved: bytes,
            n_blocks: blocks,
            key_step,
        };

        let mut resources = input.resources.clone();
        if matches!(input.kind, CallClaimKind::Const) {
            for (shader_name, resource_name) in [
                ("call_generic_claim_count_out", "call_arg_row_count_out"),
                ("call_generic_claim_callee", "call_const_claim_callee"),
                ("call_generic_claim_slot", "call_const_claim_slot"),
                ("call_generic_claim_type", "call_const_claim_len"),
            ] {
                resources.alias(shader_name, resource_name)?;
            }
        }
        let dispatch_params = uniform_from_val(
            device,
            &format!("{}.dispatch.params", definition.label()),
            &params(0),
        );
        let dispatch = reflected_bind_group_with_overrides(
            device,
            &format!("{}.dispatch", definition.label()),
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &resources,
            &[
                ("gParams", dispatch_params.as_entire_binding()),
                ("name_count_in", input.resources[names.count].clone()),
                (
                    "radix_dispatch_args",
                    input.dispatch_args.as_entire_binding(),
                ),
            ],
        )?;

        let sort = definition.operation(
            device,
            passes,
            &resources,
            input.claim_capacity,
            0,
            call_claim_radix_steps(input.token_capacity, input.claim_capacity),
            RadixSortDispatch {
                small: RadixDispatchDomain::Direct(256),
                rows: RadixDispatchDomain::Indirect(input.dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS * 256),
                bucket_bases: RadixDispatchDomain::Direct(256),
            },
            params,
        )?;

        Ok(Self {
            dispatch_pass: passes
                .kernel("type_checker/names/radix/dispatch_args")
                .clone(),
            _dispatch_params: dispatch_params,
            dispatch,
            dispatch_args: input.dispatch_args.clone(),
            sort,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_compute(
            encoder,
            &self.dispatch_pass,
            &self.dispatch,
            "type_check.calls.claim_radix_dispatch_args",
            1,
        )?;
        self.sort.record(encoder)
    }

    pub(in crate::type_checker) fn dispatch_args(&self) -> &LaniusBuffer<u32> {
        &self.dispatch_args
    }
}
