import Lanius.Memory

namespace Lanius.Memory

theorem loadBytesFrom_prefix
    {heap : Heap} {pointer offset count requested : Nat} {bytes : List UInt8}
    (loaded : loadBytesFrom heap pointer offset count = .ok bytes)
    (within : requested ≤ count) :
    loadBytesFrom heap pointer offset requested = .ok (bytes.take requested) := by
  induction count generalizing offset requested bytes with
  | zero =>
      have : requested = 0 := by omega
      subst requested
      simp [loadBytesFrom]
  | succ count ih =>
      cases requested with
      | zero => simp [loadBytesFrom]
      | succ requested =>
          cases first : heap.loadByte pointer offset with
          | error reason => simp [loadBytesFrom, first] at loaded
          | ok byte =>
              cases rest : loadBytesFrom heap pointer (offset + 1) count with
              | error reason => simp [loadBytesFrom, first, rest] at loaded
              | ok tail =>
                  simp only [loadBytesFrom, first, rest, Except.ok.injEq] at loaded
                  subst bytes
                  simp [loadBytesFrom, first,
                    ih (requested := requested) rest (by omega)]

theorem Heap.loadBytes_prefix
    {heap : Heap} {pointer count requested : Nat} {bytes : List UInt8}
    (loaded : heap.loadBytes pointer count = .ok bytes)
    (within : requested ≤ count) :
    heap.loadBytes pointer requested = .ok (bytes.take requested) :=
  loadBytesFrom_prefix loaded within

end Lanius.Memory
