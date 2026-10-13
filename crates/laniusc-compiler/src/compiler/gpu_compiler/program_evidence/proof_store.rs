//! Storage planning for GPU-owned implementation proof closures.
//!
//! A non-Clone session owns the latest accepted prefix. Plans and counts confer
//! no proof authority. Capability entry points require the dispatcher's opaque
//! owned readback; callers cannot mint a receipt or root from independently
//! supplied arrays. Raw validation helpers remain private. Binding8 owns its projection-node span.

use std::sync::Arc;
use anyhow::{Result, ensure};
use super::{abi::{INVALID, ArenaCopy, add, mul}, dispatch::GpuProofReadback};

pub(super) const PROOF_STORE_MAGIC: u32 = 0x5050_5332;
pub(super) const PROOF_STORE_VERSION: u32 = 4;
pub(super) const PROOF_STORE_TABLES: usize = 16;
pub(super) const PROOF_STORE_PERSISTENT: usize = 8;
pub(super) const PROOF_STORE_WIDTHS: [u32; PROOF_STORE_TABLES] =
    [8, 2, 2, 8, 4, 8, 8, 4, 16, 4, 4, 1, 2, 2, 8, 2];
pub(super) const PROOF_STORE_DIRECTORY: u32 = 12;
pub(super) const PROOF_STORE_FIXED_WORDS: u32 =
    PROOF_STORE_DIRECTORY + PROOF_STORE_TABLES as u32 * 6;

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct ProofStoreSlice {
    pub offset: u32,
    pub capacity: u32,
}

/// Descriptive layout only. Cloning a layout does not clone acceptance authority.
#[derive(Clone, Debug)]
pub(super) struct ProofStoreLayout {
    epoch: u64,
    arena_id: u64,
    serial: u32,
    pub slices: [ProofStoreSlice; PROOF_STORE_TABLES],
    pub word_count: u32,
}

#[derive(Debug)]
pub(super) struct ProofStoreUpload {
    pub layout: ProofStoreLayout,
    /// Only the fixed header is uploaded. Copy the accepted prefix from the
    /// session's exact owned old buffer before using the new header/layout.
    pub header: Vec<u32>,
    pub copies: Vec<ArenaCopy>,
}

/// One ledger per dispatcher-owned buffer lineage. It cannot be cloned or
/// replaced with an older receipt. Physical allocation/upload failure requires
/// discarding the owning dispatcher packet; a plan is not a completed copy.
#[derive(Debug)]
pub(super) struct ProofStoreSession {
    identity: Arc<()>,
    layout: ProofStoreLayout,
    accepted_serial: u32,
    accepted: [u32; PROOF_STORE_PERSISTENT],
}

/// Symbolic roots may be retained, but cannot authorize native replay.
#[derive(Clone, Debug)]
pub(super) struct OwnedProofRoot {
    identity: Arc<()>,
    serial: u32,
    row: u32,
    conclusion: u32,
    concrete: bool,
}

impl ProofStoreSession {
    pub fn allocate(
        epoch: u64,
        arena_id: u64,
        serial: u32,
        capacities: [u32; PROOF_STORE_TABLES],
    ) -> Result<(Self, ProofStoreUpload)> {
        let upload = ProofStoreLayout::plan(epoch, arena_id, serial, capacities, None)?;
        let session = Self {
            identity: Arc::new(()), layout: upload.layout.clone(),
            accepted_serial: 0, accepted: [0; PROOF_STORE_PERSISTENT],
        };
        Ok((session, upload))
    }

    pub fn layout(&self) -> &ProofStoreLayout { &self.layout }

    /// Descriptive storage bounds for allocation planning, never a receipt or
    /// independently restorable proof authority.
    pub fn accepted_prefix(&self) -> &[u32; PROOF_STORE_PERSISTENT] { &self.accepted }

    pub fn check_submission(&self, epoch: u64, arena_id: u64, serial: u32) -> Result<()> {
        ensure!(self.layout.epoch == epoch && self.layout.arena_id == arena_id
            && self.layout.serial == serial, "proof store belongs to another submission");
        Ok(())
    }

    /// Only the dispatch module can construct this exact-buffer readback.
    pub fn accept_gpu_readback(&mut self, readback: &GpuProofReadback) -> Result<()> {
        let (receipt, header) = readback.parts_for(
            self.layout.epoch, self.layout.arena_id, self.layout.serial)?;
        self.accept_gpu_receipt(receipt, header)
    }

    /// Source provenance is derived by ProgramPacket; output rows themselves
    /// come exclusively from the opaque readback that accepted this submission.
    pub fn root_from_gpu_readback(&self, readback: &GpuProofReadback, source: [u32; 4]) -> Result<OwnedProofRoot> {
        let (result, evidence) = readback.root_for(
            self.layout.epoch, self.layout.arena_id, self.accepted_serial, source[3])?;
        self.root_from_gpu_result(result, evidence, source)
    }

    /// Growth/retry copies exactly the latest accepted ledger prefix. A failed
    /// active serial may be retried; an accepted serial can never be reused.
    pub fn grow(
        &mut self,
        serial: u32,
        capacities: [u32; PROOF_STORE_TABLES],
    ) -> Result<ProofStoreUpload> {
        ensure!(serial >= self.layout.serial && serial > self.accepted_serial,
            "proof growth would rewind an active or accepted submission");
        let upload = ProofStoreLayout::plan(
            self.layout.epoch, self.layout.arena_id, serial, capacities, Some(self))?;
        self.layout = upload.layout.clone();
        Ok(upload)
    }

    /// Private capability boundary. The dispatcher reads this complete header
    /// and status from this session's exact owned buffer,
    /// after catalog/batch/context/call acceptance, in the same readback batch.
    /// Do not expose a public wrapper accepting caller-supplied receipt arrays.
    fn accept_gpu_receipt(&mut self, receipt: [u32; 8], header: &[u32]) -> Result<()> {
        ensure!(self.layout.serial > self.accepted_serial,
            "proof submission was already accepted");
        ensure!(receipt[0] == 1 && receipt[6] == self.layout.serial && receipt[7] == 0,
            "proof receipt is incomplete, failed, or belongs to another submission");
        // Receipt words1..5 are diagnostic fields, not ownership identities.
        // Ownership/physical layout come from the exact owned arena header.
        ensure!(header.len() == PROOF_STORE_FIXED_WORDS as usize,
            "proof readback header has invalid width");
        ensure!(header[0] == PROOF_STORE_MAGIC && header[1] == PROOF_STORE_VERSION
            && header[2] == self.layout.epoch as u32 && header[3] == (self.layout.epoch >> 32) as u32
            && header[4] == self.layout.arena_id as u32 && header[5] == (self.layout.arena_id >> 32) as u32
            && header[6] == self.layout.serial && header[7] == self.layout.serial
            && header[8] == PROOF_STORE_TABLES as u32
            && header[9] == PROOF_STORE_DIRECTORY && header[10] == 1 && header[11] == 0,
            "proof header belongs to another owned layout");
        let mut next = [0; PROOF_STORE_PERSISTENT];
        for table in 0..PROOF_STORE_TABLES {
            let base = PROOF_STORE_DIRECTORY as usize + table * 6;
            let row = &header[base..base + 6];
            let slice = self.layout.slices[table];
            ensure!(row[0] == slice.offset && row[2] == slice.capacity
                && row[5] == PROOF_STORE_WIDTHS[table], "proof directory differs from owned layout");
            let (reserved, admitted, accepted) = (row[1], row[3], row[4]);
            ensure!(reserved != INVALID && accepted <= admitted && admitted <= reserved
                && reserved <= slice.capacity, "proof receipt exceeds admitted table storage");
            if table < PROOF_STORE_PERSISTENT {
                ensure!(accepted >= self.accepted[table], "proof receipt drops an accepted prefix");
                ensure!(accepted == admitted && admitted == reserved,
                    "proof receipt leaves persistent closure rows unaccepted");
                next[table] = accepted;
            } else {
                ensure!(accepted == 0, "temporary solver work escaped as accepted proof storage");
            }
        }
        // Commit only after every table and the exact layout pass. An error
        // never advances a serial or partially changes accepted prefix bounds.
        self.accepted = next;
        self.accepted_serial = self.layout.serial;
        Ok(())
    }

    /// Private minting boundary, paired with the same exact readback operation
    /// as acceptance. `source` must be derived from the retained packet, never
    /// an independent caller tuple. No row/boolean capability constructor exists.
    fn root_from_gpu_result(
        &self,
        result: [u32; 8],
        evidence: [u32; 8],
        source: [u32; 4], // predicate, environment, call, obligation
    ) -> Result<OwnedProofRoot> {
        ensure!(self.accepted_serial != 0 && self.accepted_serial == self.layout.serial,
            "proof root needs the exact latest accepted submission");
        ensure!(matches!(result[0], 1 | 2) && result[2] == source[3],
            "proof result failed or names another source obligation");
        ensure!(evidence[0] == result[0] && evidence[1] == source[0]
            && evidence[2] == source[1] && evidence[5] == source[2]
            && evidence[6] == source[3] && evidence[7] == 0,
            "proof root provenance differs from the source obligation");
        let row = evidence[3];
        let conclusion = evidence[4];
        ensure!(row < self.accepted[6] && conclusion < self.accepted[3],
            "proof root or conclusion is outside the accepted closure");
        Ok(OwnedProofRoot {
            identity: self.identity.clone(), serial: self.accepted_serial,
            row, conclusion, concrete: evidence[0] == 1,
        })
    }
}

impl ProofStoreLayout {
    fn plan(
        epoch: u64,
        arena_id: u64,
        serial: u32,
        capacities: [u32; PROOF_STORE_TABLES],
        previous: Option<&ProofStoreSession>,
    ) -> Result<ProofStoreUpload> {
        ensure!(epoch != 0 && arena_id != 0 && serial != 0 && serial != INVALID,
            "proof store has a reserved owner or serial");
        let mut slices = [ProofStoreSlice::default(); PROOF_STORE_TABLES];
        let mut word_count = PROOF_STORE_FIXED_WORDS;
        for (table, &capacity) in capacities.iter().enumerate() {
            ensure!(capacity != INVALID, "proof table capacity uses reserved row identity");
            if let Some(session) = previous {
                if table < PROOF_STORE_PERSISTENT {
                    ensure!(capacity >= session.accepted[table], "proof growth drops accepted rows");
                }
            }
            if capacity != 0 {
                slices[table] = ProofStoreSlice { offset: word_count, capacity };
                word_count = add(word_count, mul(capacity, PROOF_STORE_WIDTHS[table], "proof table")?, "proof arena")?;
            }
        }
        let accepted_serial = previous.map_or(0, |session| session.accepted_serial);
        let mut header = vec![
            PROOF_STORE_MAGIC, PROOF_STORE_VERSION, epoch as u32, (epoch >> 32) as u32,
            arena_id as u32, (arena_id >> 32) as u32, serial, accepted_serial,
            PROOF_STORE_TABLES as u32, PROOF_STORE_DIRECTORY, 0, 0,
        ];
        let mut copies = Vec::new();
        for table in 0..PROOF_STORE_TABLES {
            let slice = slices[table];
            let count = previous.map_or(0, |session| {
                if table < PROOF_STORE_PERSISTENT { session.accepted[table] } else { 0 }
            });
            header.extend([slice.offset, count, slice.capacity, count, count, PROOF_STORE_WIDTHS[table]]);
            if let Some(session) = previous {
                if count != 0 {
                    let old = &session.layout;
                    ensure!(count <= old.slices[table].capacity, "proof ledger exceeds old storage");
                    copies.push(ArenaCopy {
                        from_word: old.slices[table].offset,
                        to_word: slice.offset,
                        word_count: mul(count, PROOF_STORE_WIDTHS[table], "accepted proof copy")?,
                    });
                }
            }
        }
        ensure!(header.len() == PROOF_STORE_FIXED_WORDS as usize, "proof directory width drift");
        Ok(ProofStoreUpload {
            layout: Self { epoch, arena_id, serial, slices, word_count }, header, copies,
        })
    }
}

impl OwnedProofRoot {
    pub fn validate_retained(&self, session: &ProofStoreSession) -> Result<()> {
        ensure!(Arc::ptr_eq(&self.identity, &session.identity)
            && self.serial != 0 && self.serial <= session.accepted_serial,
            "proof root belongs to another retained program session");
        ensure!(self.row < session.accepted[6] && self.conclusion < session.accepted[3],
            "proof root or conclusion is outside the latest accepted closure");
        Ok(())
    }
    pub fn require_concrete(&self, session: &ProofStoreSession) -> Result<u32> {
        self.validate_retained(session)?;
        ensure!(self.concrete, "symbolic proof cannot authorize native replay");
        Ok(self.row)
    }
    /// A record-consistency check, not ownership authority. Callers validate
    /// retention against the session and check the remaining source fields.
    pub fn matches_evidence(&self, evidence: [u32; 8]) -> bool {
        evidence[0] == (if self.concrete { 1 } else { 2 })
            && evidence[3] == self.row && evidence[4] == self.conclusion
    }
    pub fn is_concrete(&self) -> bool { self.concrete }
    pub fn conclusion(&self) -> u32 { self.conclusion }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn complete_header(upload: &ProofStoreUpload, count: u32) -> Vec<u32> {
        let mut header = upload.header.clone();
        header[7] = header[6];
        header[10] = 1;
        for table in 0..PROOF_STORE_PERSISTENT {
            let base = PROOF_STORE_DIRECTORY as usize + table * 6;
            header[base + 1] = count;
            header[base + 3] = count;
            header[base + 4] = count;
        }
        header
    }
    fn success(serial: u32) -> [u32; 8] { [1, 0, 0, 0, 0, 0, serial, 0] }
    fn root(session: &ProofStoreSession, row: u32) -> OwnedProofRoot {
        session.root_from_gpu_result([1, 0, 7, 0, 0, 0, 0, 0],
            [1, 4, 5, row, row, 6, 7, 0], [4, 5, 6, 7]).unwrap()
    }

    #[test]
    fn accepted_growth_preserves_newer_roots_and_rejects_rollback() {
        let (mut session, first) = ProofStoreSession::allocate(1, 2, 1, [4; PROOF_STORE_TABLES]).unwrap();
        session.accept_gpu_receipt(success(1), &complete_header(&first, 1)).unwrap();
        let second = session.grow(2, [4; PROOF_STORE_TABLES]).unwrap();
        session.accept_gpu_receipt(success(2), &complete_header(&second, 2)).unwrap();
        let newer = root(&session, 1);
        assert!(session.grow(3, [1; PROOF_STORE_TABLES]).is_err());
        let third = session.grow(3, [4; PROOF_STORE_TABLES]).unwrap();
        assert_eq!(third.header[7], 2);
        assert_eq!(third.copies.len(), PROOF_STORE_PERSISTENT);
        assert!(session.accept_gpu_receipt(success(3), &complete_header(&third, 1)).is_err());
        assert_eq!(session.accepted_serial, 2);
        assert_eq!(session.accepted, [2; PROOF_STORE_PERSISTENT]);
        assert!(session.accept_gpu_receipt(success(2), &complete_header(&third, 3)).is_err());
        assert!(session.accept_gpu_receipt([0; 8], &complete_header(&third, 3)).is_err());
        assert_eq!(session.accepted_serial, 2);
        session.accept_gpu_receipt(success(3), &complete_header(&third, 3)).unwrap();
        assert_eq!(newer.require_concrete(&session).unwrap(), 1);
        assert!(session.accept_gpu_receipt(success(3), &complete_header(&third, 3)).is_err());
        assert!(session.grow(2, [4; PROOF_STORE_TABLES]).is_err());
    }

    #[test]
    fn root_authority_uses_session_identity_and_both_accepted_bounds() {
        let (mut session, upload) = ProofStoreSession::allocate(1, 2, 1, [4; PROOF_STORE_TABLES]).unwrap();
        session.accept_gpu_receipt(success(1), &complete_header(&upload, 2)).unwrap();
        let accepted = root(&session, 1);
        let (mut foreign, other) = ProofStoreSession::allocate(1, 2, 1, [4; PROOF_STORE_TABLES]).unwrap();
        foreign.accept_gpu_receipt(success(1), &complete_header(&other, 2)).unwrap();
        assert!(accepted.require_concrete(&foreign).is_err());
        let mut invalid = accepted.clone();
        invalid.row = 2;
        assert!(invalid.require_concrete(&session).is_err());
        invalid.row = 1;
        invalid.conclusion = 2;
        assert!(invalid.require_concrete(&session).is_err());
        invalid.conclusion = 1;
        invalid.concrete = false;
        assert!(invalid.require_concrete(&session).is_err());
    }

    #[test]
    fn acceptance_is_atomic_and_validates_the_owned_header() {
        let (mut session, upload) = ProofStoreSession::allocate(1, 2, 1, [4; PROOF_STORE_TABLES]).unwrap();
        for case in 0..8 {
            let mut header = complete_header(&upload, 1);
            match case {
                0 => header[4] = 99,
                1 => header[PROOF_STORE_DIRECTORY as usize + 7 * 6 + 4] = 0,
                2 => header[PROOF_STORE_DIRECTORY as usize + 8 * 6 + 4] = 1,
                3 => header[PROOF_STORE_DIRECTORY as usize + 7 * 6] += 1,
                4 => header[7] = 0,
                5 => header[10] = 0,
                // The old Binding4 layout must never be accepted as Binding8.
                6 => header[PROOF_STORE_DIRECTORY as usize + 5 * 6 + 5] = 4,
                7 => header[1] = 3,
                _ => unreachable!(),
            }
            assert!(session.accept_gpu_receipt(success(1), &header).is_err());
            assert_eq!(session.accepted_serial, 0);
            assert_eq!(session.accepted, [0; PROOF_STORE_PERSISTENT]);
        }
    }
}
