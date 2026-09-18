import Lanius.Extraction.Allocation.Sequence

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics

theorem HostReady.rootLower (history : HostReady buffers before ready)
    (names : (buffers.map Buffer.binding).Nodup) (buffer : Buffer) (member : buffer ∈ buffers)
    (read : ready.local? buffer.binding = some (.slice (.scalar (.signed .i32)) root [] 0 length)) :
    before.nextCell ≤ root := by
  induction buffers generalizing before with
  | nil => simp at member
  | cons head tail ih =>
      have distinct := List.nodup_cons.mp names
      rcases List.mem_cons.mp member with same | member
      · subst buffer
        have known := history.head_read distinct.1
        rw [known] at read
        cases read
        exact Nat.le_add_right _ _
      · cases history with
        | cons initialized rest =>
            have lower := ih rest distinct.2 member
            rw [initialized.next] at lower
            exact Nat.le_trans (Nat.le_add_right _ _) lower

theorem HostReady.rootsDistinct (history : HostReady buffers before ready)
    (names : (buffers.map Buffer.binding).Nodup) (left right : Buffer)
    (leftMember : left ∈ buffers) (rightMember : right ∈ buffers)
    (different : left.binding ≠ right.binding)
    (leftRead : ready.local? left.binding = some (.slice (.scalar (.signed .i32)) leftRoot [] 0 leftLength))
    (rightRead : ready.local? right.binding = some (.slice (.scalar (.signed .i32)) rightRoot [] 0 rightLength)) :
    leftRoot ≠ rightRoot := by
  induction buffers generalizing before with
  | nil => simp at leftMember
  | cons head tail ih =>
      have distinct := List.nodup_cons.mp names
      rcases List.mem_cons.mp leftMember with leftHead | leftTail
      · subst left
        have known := history.head_read distinct.1
        rw [known] at leftRead
        cases leftRead
        have rightTail : right ∈ tail := by
          rcases List.mem_cons.mp rightMember with same | member
          · subst right; exact False.elim (different rfl)
          · exact member
        cases history with
        | cons initialized rest =>
            have lower := rest.rootLower distinct.2 right rightTail rightRead
            rw [initialized.next] at lower
            exact Nat.ne_of_lt (Nat.lt_of_lt_of_le (Nat.lt_succ_self _) lower)
      · rcases List.mem_cons.mp rightMember with rightHead | rightTail
        · subst right
          have known := history.head_read distinct.1
          rw [known] at rightRead
          cases rightRead
          cases history with
          | cons initialized rest =>
              have lower := rest.rootLower distinct.2 left leftTail leftRead
              rw [initialized.next] at lower
              exact Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le (Nat.lt_succ_self _) lower))
        · cases history with
          | cons initialized rest =>
              exact ih rest distinct.2 leftTail rightTail

end Lanius.Extraction.Allocation
