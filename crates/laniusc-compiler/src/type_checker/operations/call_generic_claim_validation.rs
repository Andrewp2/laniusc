use super::super::*;
use crate::gpu::operations::StepProgramOperation;

pub(in crate::type_checker) struct CallGenericClaimValidationBuild {
    /// Generic and constant claim offsets, one paired scan. Its apply writes
    /// both claim indexes' dispatch arguments.
    pub claim_scans: PrefixScanPairOperation,
    pub emit_claims: ComputeOperation,
    pub build_indexes: StepProgramOperation,
    pub validate_generic: ComputeOperation,
    pub mark_required: ComputeOperation,
    /// Its apply writes the required-binding dispatch arguments.
    pub required_scan: PrefixScanOperation,
    /// The dispatch uniforms of the claim and required-binding scan applies.
    pub dispatch_params: [LaniusBuffer<CountDispatchParams>; 2],
    pub validate_required: ComputeOperation,
    pub validate_const: ComputeOperation,
}

/// Compiled GPU operation that collects provisional call claims and validates
/// complete generic bindings after expression inference closes.
///
/// Prefix scans, exact indexes, and dispatch generation are private steps.
/// The recorder schedules claim collection during inference, and marks required
/// bindings and validates strict type and constant conflicts and required
/// bindings together after closure.
pub(in crate::type_checker) struct CallGenericClaimValidationOperation {
    claim_scans: PrefixScanPairOperation,
    emit_claims: ComputeOperation,
    build_indexes: StepProgramOperation,
    validate_generic: ComputeOperation,
    mark_required: ComputeOperation,
    required_scan: PrefixScanOperation,
    _dispatch_params: [LaniusBuffer<CountDispatchParams>; 2],
    validate_required: ComputeOperation,
    validate_const: ComputeOperation,
}

impl CallGenericClaimValidationOperation {
    pub(in crate::type_checker) fn new(build: CallGenericClaimValidationBuild) -> Self {
        Self {
            claim_scans: build.claim_scans,
            emit_claims: build.emit_claims,
            build_indexes: build.build_indexes,
            validate_generic: build.validate_generic,
            mark_required: build.mark_required,
            required_scan: build.required_scan,
            _dispatch_params: build.dispatch_params,
            validate_required: build.validate_required,
            validate_const: build.validate_const,
        }
    }

    pub(in crate::type_checker) fn record_claims(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pages: &DependencyPatternReplay<'_>,
    ) -> Result<()> {
        self.claim_scans.record(encoder)?;
        pages.record(encoder, |encoder| self.emit_claims.record(encoder))?;
        self.build_indexes.record(encoder)

    }

    pub(in crate::type_checker) fn record_required(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        // Only the required-binding validation reads the marks, so they are
        // made once, from the closed inference facts.
        self.mark_required.record(encoder)?;
        self.required_scan.record(encoder)?;
        self.validate_generic.record(encoder)?;
        self.validate_const.record(encoder)?;
        self.validate_required.record(encoder)
    }
}
