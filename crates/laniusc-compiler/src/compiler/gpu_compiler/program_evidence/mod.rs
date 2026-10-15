//! Owned definition snapshots and append-only call/evidence packets.
//! Graph comparison and implementation selection belong to GPU consumers.
//! Every issued row retains its immutable owner and referenced row closure.

mod abi;
mod catalog;
mod dispatch;
mod native_layout;
mod native_layout_work;
mod native_session;
mod packet;
mod proof_store;

pub(super) use dispatch::EvidenceWorkspacePool;

pub(super) use abi::{ArenaCopy, ArenaWrite, OutputRange, UploadPlan};
pub(super) use catalog::{CatalogInput, FrozenCatalog, FrozenSnapshotId, StableWitnessIdentity};
pub(super) use native_session::{
    NativeProgramSession,
    ReplayScope,
    ValidatedOriginalUnit,
    ValidatedReplayRequest,
    native_program_error,
};
pub(super) use packet::{
    AdmittedCall,
    ProgramPacket,
    ReplayContextInput,
    SourceCallIdentity,
    Submission,
    ValidatedEvidence,
};

// Callable native identities come from accepted owner retention; actual public
// aliases are joined against the accepted interface, never guessed from tags.
