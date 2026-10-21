import Lanius.Semantics

namespace Lanius.Semantics

theorem encodeNatLE_succ (width value : Nat) :
    encodeNatLE (width + 1) value =
      UInt8.ofNat (value % 256) :: encodeNatLE width (value / 256) := by
  simp only [encodeNatLE, List.range_succ_eq_map, List.map_cons, List.map_map,
    Nat.pow_zero, Nat.div_one]
  congr 1
  apply List.map_congr_left
  intro index _
  simp only [Function.comp_def, Nat.pow_succ, Nat.div_div_eq_div_mul]
  rw [Nat.mul_comm (256 ^ index) 256]

/-- Native integers and enum tags round-trip at their declared byte width.
    The bound is essential: wider mathematical values would be truncated. -/
theorem decodeNatLE_encodeNatLE (width value : Nat) (fits : value < 256 ^ width) :
    decodeNatLE (encodeNatLE width value) = value := by
  induction width generalizing value with
  | zero =>
      have : value = 0 := by simpa using fits
      simp [encodeNatLE, decodeNatLE, this]
  | succ width ih =>
      rw [encodeNatLE_succ, decodeNatLE]
      have quotient : value / 256 < 256 ^ width := by
        apply (Nat.div_lt_iff_lt_mul (by decide)).mpr
        simpa only [Nat.pow_succ] using fits
      rw [ih _ quotient]
      rw [UInt8.toNat_ofNat_of_lt' (Nat.mod_lt _ (by decide : 0 < 256))]
      exact Nat.mod_add_div _ _

theorem loadNatLE_of_encoded (loaded : heap.loadBytes address width = .ok (encodeNatLE width value))
    (fits : value < 256 ^ width) : loadNatLE heap address width = .ok value := by
  simp only [loadNatLE, loaded]
  change Except.ok (decodeNatLE (encodeNatLE width value)) = Except.ok value
  rw [decodeNatLE_encodeNatLE width value fits]

end Lanius.Semantics
