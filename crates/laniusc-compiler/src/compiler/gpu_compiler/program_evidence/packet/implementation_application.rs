//! An implementation application is authority retained from one exact call and
//! proof closure. Materialized types and wire rows alone cannot construct it.
use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};

use super::{
    super::{
        abi::INVALID,
        dispatch::{MaterializedProofType, ProjectedImplApplication},
        native_layout_work::NativeLayoutSource,
    },
    AdmittedCall,
    OwnedProofRoot,
    ProgramPacket,
    ValidatedEvidence,
};
use crate::{
    constant_value::CheckedConstantValue,
    type_checker::{
        CheckedGenericArgument,
        CheckedGenericConstant,
        CheckedGenericConstantValue,
        CheckedGenericParameter,
        CheckedParameterDomain,
    },
};

pub(in crate::compiler::gpu_compiler::program_evidence) struct ImplApplicationRequest {
    origin: AdmittedCall,
    evidence: ValidatedEvidence,
    root: OwnedProofRoot,
    subject_slot: u32,
    identity: Arc<()>,
    rows: [u32; 8],
}

impl ImplApplicationRequest {
    pub(in crate::compiler::gpu_compiler::program_evidence) fn checked_rows(
        &self,
        packet: &ProgramPacket,
    ) -> Result<[u32; 8]> {
        let (root, slot, rows) =
            packet.implementation_request_source(&self.origin, &self.evidence)?;
        root.require_concrete(&packet.proof_store)?;
        ensure!(
            slot == self.subject_slot && rows == self.rows,
            "implementation request lost its exact evidence occurrence"
        );
        Ok(rows)
    }
    pub(in crate::compiler::gpu_compiler::program_evidence) fn identity(&self) -> Arc<()> {
        self.identity.clone()
    }
}

pub(in crate::compiler::gpu_compiler::program_evidence) struct AdmittedImplementationMethod {
    trait_unit: [u32; 2],
    required_symbol: u32,
    target: [u32; 3],
    receiver_mode: u32,
    required_types: u32,
    required_constants: u32,
}
impl AdmittedImplementationMethod {
    pub fn required_trait_unit(&self) -> [u32; 2] {
        self.trait_unit
    }
    pub fn required_symbol(&self) -> u32 {
        self.required_symbol
    }
    pub fn target(&self) -> [u32; 3] {
        self.target
    }
    pub fn receiver_mode(&self) -> u32 {
        self.receiver_mode
    }
    pub fn requirements(&self) -> (u32, u32) {
        (self.required_types, self.required_constants)
    }
}

pub(in crate::compiler::gpu_compiler::program_evidence) struct AdmittedImplementationApplication {
    request: ImplApplicationRequest,
    /// Retains the opaque successful readback and its assumption/prerequisite
    /// provenance. It is never converted into new table-17 root evidence.
    projection: ProjectedImplApplication,
    implementation_owner: u32,
    parameters: Box<[CheckedGenericParameter]>,
    arguments: Box<[CheckedGenericArgument]>,
    constants: Box<[CheckedGenericConstant]>,
    methods: Box<[AdmittedImplementationMethod]>,
}
impl AdmittedImplementationApplication {
    pub fn origin(&self) -> &AdmittedCall {
        &self.request.origin
    }
    pub fn subject_slot(&self) -> u32 {
        self.request.subject_slot
    }
    pub fn implementation(&self) -> u32 {
        self.projection.implementation()
    }
    pub fn arguments(&self) -> &[CheckedGenericArgument] {
        &self.arguments
    }
    pub fn constants(&self) -> &[CheckedGenericConstant] {
        &self.constants
    }
    pub fn methods(&self) -> &[AdmittedImplementationMethod] {
        &self.methods
    }
    pub fn implementation_owner(&self) -> u32 {
        self.implementation_owner
    }
    pub fn parameters(&self) -> &[CheckedGenericParameter] {
        &self.parameters
    }
    /// An admitted old root remains valid through monotone accepted growth.
    /// Exact-current serial validation belongs to raw projection receipt mint.
    pub fn validate_retained(&self, packet: &ProgramPacket) -> Result<()> {
        self.request.checked_rows(packet)?;
        self.request.root.require_concrete(&packet.proof_store)?;
        self.projection
            .validate_retained_source(&self.request, packet)?;
        Ok(())
    }
}

impl ProgramPacket {
    pub(in crate::compiler::gpu_compiler::program_evidence) fn check_implementation_projection_owner(
        &self,
        epoch: u64,
        arena_id: u64,
        serial: Option<u32>,
    ) -> Result<()> {
        self.ready()?;
        ensure!(
            epoch == self.catalog.epoch && arena_id == self.arena_id,
            "implementation projection belongs to another catalog or arena"
        );
        if let Some(serial) = serial {
            self.proof_store.check_submission(epoch, arena_id, serial)?;
        }
        Ok(())
    }
    fn implementation_request_source(
        &self,
        origin: &AdmittedCall,
        evidence: &ValidatedEvidence,
    ) -> Result<(OwnedProofRoot, u32, [u32; 8])> {
        let (_, _, _, obligations) = self.replay_origin(origin)?;
        ensure!(
            evidence.epoch == self.catalog.epoch && evidence.arena_id == self.arena_id,
            "implementation evidence belongs to another catalog or arena"
        );
        let root = evidence
            .proof
            .as_ref()
            .ok_or_else(|| anyhow!("refuted implementation evidence"))?;
        let root_row = root.require_concrete(&self.proof_store)?;
        let retained: [u32; 8] = self.tables.row(17, evidence.input_row)?.try_into()?;
        ensure!(
            root.matches_evidence(retained) && retained[0] == 1 && retained[7] == 0,
            "implementation evidence differs from its retained accepted root"
        );
        let ordinal = retained[6].checked_sub(obligations.first).ok_or_else(|| {
            anyhow!("implementation evidence precedes the exact origin obligation span")
        })?;
        ensure!(
            ordinal < obligations.count,
            "implementation evidence is outside the exact origin obligation span"
        );
        let obligation = self.tables.row(16, retained[6])?;
        let call = self.tables.row(15, origin.row)?;
        ensure!(
            obligation == &[origin.row, evidence.predicate_row, call[4], 0]
                && retained[1] == evidence.predicate_row
                && retained[2] == call[4]
                && retained[5] == origin.row,
            "implementation evidence has another origin, ordinal, predicate or environment"
        );
        let callable_owner = self.catalog.tables.row(4, call[3])?[1];
        let predicates = self.catalog.applicable_predicates(callable_owner)?;
        ensure!(
            predicates.get(ordinal as usize) == Some(&evidence.predicate_row),
            "implementation evidence ordinal does not name the definition predicate"
        );
        let slot = self
            .catalog
            .predicate_subject_slot(evidence.predicate_row)?
            .ok_or_else(|| {
                anyhow!("UNSUPPORTED: implementation predicate subject is not a type slot")
            })?;
        Ok((
            root.clone(),
            slot,
            [
                root_row,
                root.conclusion(),
                origin.row,
                // accept_submission retains this evidence on the CPU after
                // its input upload. The current output obligation already
                // exists on the GPU; table 17 may not be uploaded until a
                // later submission. The CPU table-17 join above is mandatory.
                retained[6],
                evidence.predicate_row,
                slot,
                call[0],
                0,
            ],
        ))
    }

    pub(in crate::compiler::gpu_compiler::program_evidence) fn request_implementation_application(
        &self,
        origin: &AdmittedCall,
        evidence: &ValidatedEvidence,
    ) -> Result<ImplApplicationRequest> {
        let (root, subject_slot, rows) = self.implementation_request_source(origin, evidence)?;
        Ok(ImplApplicationRequest {
            origin: origin.clone(),
            evidence: evidence.clone(),
            root,
            subject_slot,
            identity: Arc::new(()),
            rows,
        })
    }

    pub(in crate::compiler::gpu_compiler::program_evidence) fn admit_implementation_application(
        &self,
        request: ImplApplicationRequest,
        projection: ProjectedImplApplication,
        types: Vec<MaterializedProofType>,
    ) -> Result<Arc<AdmittedImplementationApplication>> {
        request.checked_rows(self)?;
        projection.validate_current(&request, self)?;
        ensure!(
            request
                .evidence
                .implementation
                .is_none_or(|row| row == projection.implementation()),
            "implementation projection disagrees with the retained selected implementation"
        );
        let contract = self
            .catalog
            .implementation_application_contract(projection.implementation())?;
        ensure!(
            contract.owner == projection.owner()
                && contract.parameters.len() == projection.bindings().len()
                && contract.prerequisites.count as usize == projection.prerequisites().len(),
            "implementation projection differs from its exact owner contract"
        );
        for (index, prerequisite) in projection.prerequisites().iter().enumerate() {
            ensure!(
                prerequisite[0] == contract.prerequisites.first + index as u32,
                "implementation prerequisite order differs from its own binder"
            );
        }
        let mut types = types.into_iter();
        let mut arguments = Vec::new();
        let mut constants = Vec::new();
        let mut parameters = Vec::new();
        for ((parameter_row, parameter), binding) in
            contract.parameters.iter().zip(projection.bindings())
        {
            let domain = u32::from(parameter.identity.domain == CheckedParameterDomain::Constant);
            ensure!(
                binding[0] == *parameter_row
                    && binding[1] == domain
                    && binding[2] == parameter.binding_slot
                    && binding[3] == parameter.identity.source_ordinal,
                "implementation binding has another parameter identity or domain slot"
            );
            parameters.push(*parameter);
            if domain == 0 {
                ensure!(
                    binding[6..12] == [0; 6],
                    "type binding has unexpected constant payload"
                );
                let source = NativeLayoutSource {
                    epoch: self.catalog.epoch,
                    arena_id: self.arena_id,
                    serial: projection.serial(),
                    reference: [binding[4], binding[5]],
                };
                let data = types
                    .next()
                    .ok_or_else(|| anyhow!("implementation type data is incomplete"))?;
                let ty = data.type_for(&self.catalog, source)?.clone();
                ensure!(ty.is_closed(), "implementation type data is symbolic");
                arguments.push(CheckedGenericArgument {
                    slot: parameter.binding_slot,
                    ty,
                });
            } else {
                ensure!(
                    binding[7] == 0
                        && binding[11] == 0
                        && parameter.constant_scalar == Some(binding[6])
                        && binding[8] == binding[6],
                    "implementation constant differs from its declared scalar"
                );
                let value = CheckedConstantValue::from_words(binding[8], [binding[9], binding[10]])
                    .ok_or_else(|| anyhow!("implementation constant data has invalid shape"))?;
                constants.push(CheckedGenericConstant {
                    slot: parameter.binding_slot,
                    value: CheckedGenericConstantValue::Literal(value),
                });
            }
        }
        ensure!(
            types.next().is_none(),
            "implementation type data has unrelated extra terms"
        );
        arguments.sort_by_key(|argument| argument.slot);
        constants.sort_by_key(|constant| constant.slot);
        let mut methods = Vec::new();
        for (method, required_types, required_constants) in contract.methods {
            ensure!(
                required_types as usize == arguments.len()
                    && required_constants as usize == constants.len()
                    && method.required_symbol != INVALID
                    && method.receiver_mode <= 3,
                "implementation method has an incomplete application environment"
            );
            methods.push(AdmittedImplementationMethod {
                trait_unit: method.trait_unit,
                required_symbol: method.required_symbol,
                target: method.target,
                receiver_mode: method.receiver_mode,
                required_types,
                required_constants,
            });
        }
        Ok(Arc::new(AdmittedImplementationApplication {
            request,
            projection,
            implementation_owner: contract.owner,
            parameters: parameters.into_boxed_slice(),
            arguments: arguments.into_boxed_slice(),
            constants: constants.into_boxed_slice(),
            methods: methods.into_boxed_slice(),
        }))
    }
}
