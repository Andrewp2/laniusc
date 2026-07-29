use super::super::*;

pub(in crate::type_checker) struct CallGenericClaimValidationBuild {
    pub required_dispatch_pass: PassData,
    pub claim_scan: PrefixScanOperation,
    pub emit_claims: ComputeOperation,
    pub generic_keys: CallClaimKeyPipeline,
    pub validate_generic: ComputeOperation,
    pub mark_required: ComputeOperation,
    pub required_scan: PrefixScanOperation,
    pub required_dispatch: wgpu::BindGroup,
    pub required_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub validate_required: ComputeOperation,
    pub const_keys: CallClaimKeyPipeline,
    pub validate_const: ComputeOperation,
}

/// Compiled GPU operation that validates all generic and const-generic claims
/// emitted by compact call-argument rows.
///
/// Prefix scans, radix sorts, dispatch generation, and validation kernels are
/// private implementation steps. A caller provides only the active HIR
/// dispatch domain and cannot record an incomplete validation sequence.
pub(in crate::type_checker) struct CallGenericClaimValidationOperation {
    required_dispatch_pass: PassData,
    claim_scan: PrefixScanOperation,
    emit_claims: ComputeOperation,
    generic_keys: CallClaimKeyPipeline,
    validate_generic: ComputeOperation,
    mark_required: ComputeOperation,
    required_scan: PrefixScanOperation,
    required_dispatch: wgpu::BindGroup,
    _required_dispatch_params: LaniusBuffer<CountDispatchParams>,
    validate_required: ComputeOperation,
    const_keys: CallClaimKeyPipeline,
    validate_const: ComputeOperation,
}

impl CallGenericClaimValidationOperation {
    pub(in crate::type_checker) fn new(build: CallGenericClaimValidationBuild) -> Self {
        Self {
            required_dispatch_pass: build.required_dispatch_pass,
            claim_scan: build.claim_scan,
            emit_claims: build.emit_claims,
            generic_keys: build.generic_keys,
            validate_generic: build.validate_generic,
            mark_required: build.mark_required,
            required_scan: build.required_scan,
            required_dispatch: build.required_dispatch,
            _required_dispatch_params: build.required_dispatch_params,
            validate_required: build.validate_required,
            const_keys: build.const_keys,
            validate_const: build.validate_const,
        }
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.claim_scan.record(encoder)?;
        self.emit_claims.record(encoder)?;
        self.generic_keys.record(encoder)?;
        self.validate_generic.record(encoder)?;
        self.mark_required.record(encoder)?;
        self.required_scan.record(encoder)?;
        record_compute(
            encoder,
            &self.required_dispatch_pass,
            &self.required_dispatch,
            "type_check.calls.generic_claim_validation.required_dispatch",
            1,
        )?;
        self.validate_required.record(encoder)?;
        self.const_keys.record(encoder)?;
        self.validate_const.record(encoder)
    }
}
