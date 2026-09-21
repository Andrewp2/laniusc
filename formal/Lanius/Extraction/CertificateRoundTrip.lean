import Lanius.Extraction.Certificate

namespace Lanius.Extraction.CertificateRoundTrip

open CompactDecode

def hexDigit (n : Nat) : Char :=
  Char.ofNat (if n < 10 then 48 + n else 87 + n)

def hexNat : Nat → Nat → String
  | 0, _ => ""
  | width + 1, value =>
      let shift := width * 4
      String.ofList [hexDigit ((value / 2 ^ shift) % 16)] ++
        hexNat width value

def wordNat (value : Int) : Nat := Int.toNat (value % 4294967296)

def hexWord (value : Int) : String := hexNat 8 (wordNat value)

example : hexNat 8 3 = "00000003" := by decide
example : hexWord 42 = "0000002a" := by decide
example : hexWord (-1) = "ffffffff" := by decide

theorem digit_of_lookup (state : DecodeState) (byte : UInt8) (value : Nat)
    (lookup : state.bytes[state.offset]? = some byte)
    (digit : byte.toNat = 48 + value) (bounded : value ≤ 9) :
    (readHexDigit.run state) =
      some (value, { state with offset := state.offset + 1 }) := by
  unfold readHexDigit
  rw [StateT.run_bind, StateT.run_get]
  simp
  simp [StateT.run]
  rw [lookup]
  simp [digit]
  have bnd : 48 + value ≤ 57 := by omega
  simp [bnd]
  simp [liftM, MonadLiftT.monadLift, MonadLift.monadLift]
  rfl

theorem digit_of_lookup_lower (state : DecodeState) (byte : UInt8) (value : Nat)
    (lookup : state.bytes[state.offset]? = some byte)
    (digit : byte.toNat = 87 + value) (bounded : 10 ≤ value ∧ value < 16) :
    (readHexDigit.run state) =
      some (value, { state with offset := state.offset + 1 }) := by
  unfold readHexDigit
  rw [StateT.run_bind, StateT.run_get]
  simp
  simp [StateT.run]
  rw [lookup]
  simp [digit]
  have blo : 97 ≤ 87 + value := by omega
  have bhi : 87 + value ≤ 102 := by omega
  have bad : ¬ (48 ≤ 87 + value ∧ 87 + value ≤ 57) := by omega
  simp [blo, bhi, bad]
  simp [liftM, MonadLiftT.monadLift, MonadLift.monadLift]
  rfl

private theorem utf8_char_lookup (pre : ByteArray) (ch : Char) (ascii : Nat)
    (tail : String) (hchar : ch.toNat = ascii) (ha : ascii ≤ 127) :
    (pre ++ (String.ofList [ch] ++ tail).toUTF8)[pre.size]? =
      some (UInt8.ofNat ascii) := by
  simp [getElem?, decidableGetElem?, ByteArray.getElem_eq_getElem_data,
    String.ofList, List.utf8Encode, String.utf8EncodeChar, hchar, ha,
    String.toUTF8, String.toByteArray_append, ByteArray.data_append]
  constructor
  · omega
  · exact Array.getElem_push_eq

theorem digit_at_char (pre : ByteArray) (ch : Char) (ascii n : Nat)
    (tail : String) (hchar : ch.toNat = ascii) (ha : ascii ≤ 127)
    (hn : n ≤ 9) (hmatch : ascii = 48 + n) :
    (readHexDigit.run
      {bytes := pre ++ (String.ofList [ch] ++ tail).toUTF8, offset:=pre.size}) =
    some (n, {bytes := pre ++ (String.ofList [ch] ++ tail).toUTF8, offset:=pre.size+1}) := by
  have lookup := utf8_char_lookup pre ch ascii tail hchar ha
  apply digit_of_lookup _ _ _ lookup
  · have hsmall : 48 + n < 256 := by omega
    simp [hmatch, UInt8.ofNat]
    exact Nat.mod_eq_of_lt hsmall
  · exact hn

theorem digit_at_char_lower (pre : ByteArray) (ch : Char) (ascii n : Nat)
    (tail : String) (hchar : ch.toNat = ascii) (ha : ascii ≤ 127)
    (hn : 10 ≤ n ∧ n < 16) (hmatch : ascii = 87 + n) :
    (readHexDigit.run
      {bytes := pre ++ (String.ofList [ch] ++ tail).toUTF8, offset:=pre.size}) =
    some (n, {bytes := pre ++ (String.ofList [ch] ++ tail).toUTF8, offset:=pre.size+1}) := by
  have lookup := utf8_char_lookup pre ch ascii tail hchar ha
  apply digit_of_lookup_lower _ _ _ lookup
  · have hsmall : 87 + n < 256 := by omega
    simp [hmatch, UInt8.ofNat]
    exact Nat.mod_eq_of_lt hsmall
  · exact hn

theorem hexDigit_nat (n : Nat) (h : n < 16) :
    (hexDigit n).toNat = if n < 10 then 48 + n else 87 + n := by
  have cases : n = 0 ∨ n = 1 ∨ n = 2 ∨ n = 3 ∨ n = 4 ∨ n = 5 ∨
      n = 6 ∨ n = 7 ∨ n = 8 ∨ n = 9 ∨ n = 10 ∨ n = 11 ∨
      n = 12 ∨ n = 13 ∨ n = 14 ∨ n = 15 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

theorem hexNat_arith (w value acc : Nat) :
    (acc * 16 + (value / (16^w)) % 16) * 16^w + value % 16^w =
      acc * 16^(w+1) + value % 16^(w+1) := by
  let base := 16^w
  have hbase : 0 < base := by
    dsimp [base]
    exact Nat.pow_pos (by decide)
  have hlowdiv : (value % (base * 16)) / base = value / base % 16 := by
    exact Nat.mod_mul_right_div_self value base 16
  have hlowmod : (value % (base * 16)) % base = value % base := by
    exact Nat.mod_mul_right_mod value base 16
  have hsplit : value % (base * 16) =
      (value / base % 16) * base + value % base := by
    have h := Nat.div_add_mod (value % (base * 16)) base
    rw [hlowdiv, hlowmod] at h
    simpa [Nat.mul_comm] using h.symm
  calc
    (acc * 16 + (value / base) % 16) * base + value % base =
        acc * (base * 16) + ((value / base) % 16) * base + value % base := by
      simp [Nat.mul_add, Nat.mul_assoc, Nat.add_assoc, Nat.mul_comm]
    _ = acc * (base * 16) + value % (base * 16) := by
      rw [hsplit]
      exact Nat.add_assoc _ _ _
    _ = acc * 16 ^ (w + 1) + value % (16 ^ (w + 1)) := by
      simp [base, Nat.pow_succ, Nat.mul_comm]

theorem hexNat_read (w value acc : Nat) (pre tail : String) :
    (readHexNat w acc).run
      { bytes := pre.toUTF8 ++ (hexNat w value ++ tail).toUTF8,
        offset := pre.toUTF8.size } =
    some (acc * 16 ^ w + value % (16 ^ w),
      { bytes := pre.toUTF8 ++ (hexNat w value ++ tail).toUTF8,
        offset := pre.toUTF8.size + (hexNat w value).toUTF8.size }) := by
  induction w generalizing value acc pre tail with
  | zero =>
      simp [readHexNat, hexNat, Nat.mod_one]
  | succ w ih =>
      let base := 16 ^ w
      let digit := (value / base) % 16
      have hbase : 0 < base := by
        dsimp [base]
        exact Nat.pow_pos (by decide)
      have hpow : 2 ^ (w * 4) = base := by
        dsimp [base]
        rw [Nat.mul_comm]
        rw [Nat.pow_mul]
      have hdigit : digit < 16 := by
        dsimp [digit]
        exact Nat.mod_lt _ (by omega)
      have hchar : (hexDigit digit).toNat =
          if digit < 10 then 48 + digit else 87 + digit :=
        hexDigit_nat digit hdigit
      have hchar_size : (String.ofList [hexDigit digit]).toUTF8.size = 1 := by
        have hsmall : (hexDigit digit).toNat ≤ 127 := by
          rw [hchar]
          split <;> omega
        simp [String.ofList, List.utf8Encode, String.utf8EncodeChar, hsmall]
      have htail : (hexNat (Nat.succ w) value ++ tail) =
          (String.ofList [hexDigit digit] ++ (hexNat w value ++ tail)) := by
        simp [hexNat, digit, base, hpow, String.append_assoc]
      have hstep : (readHexDigit.run
          {bytes := pre.toUTF8 ++ (hexNat (Nat.succ w) value ++ tail).toUTF8,
           offset := pre.toUTF8.size}) =
          some (digit,
            {bytes := pre.toUTF8 ++ (hexNat (Nat.succ w) value ++ tail).toUTF8,
             offset := pre.toUTF8.size + 1}) := by
        have hstep0 : (readHexDigit.run
            {bytes := pre.toUTF8 ++
                (String.ofList [hexDigit digit] ++ (hexNat w value ++ tail)).toUTF8,
             offset := pre.toUTF8.size}) =
            some (digit,
              {bytes := pre.toUTF8 ++
                  (String.ofList [hexDigit digit] ++ (hexNat w value ++ tail)).toUTF8,
               offset := pre.toUTF8.size + 1}) := by
          by_cases hd : digit < 10
          · exact digit_at_char pre.toUTF8 (hexDigit digit) (48 + digit) digit
              (hexNat w value ++ tail) (by simpa [hd] using hchar) (by omega)
              (by omega) rfl
          · exact digit_at_char_lower pre.toUTF8 (hexDigit digit) (87 + digit) digit
              (hexNat w value ++ tail) (by simpa [hd] using hchar) (by omega)
              (by constructor <;> omega) rfl
        simpa only [htail] using hstep0
      have hread := ih value (acc * 16 + digit)
        (pre ++ String.ofList [hexDigit digit]) tail
      have hbytes :
          (pre ++ String.ofList [hexDigit digit]).toUTF8 ++
              (hexNat w value ++ tail).toUTF8 =
            pre.toUTF8 ++ (String.ofList [hexDigit digit] ++
              (hexNat w value ++ tail)).toUTF8 := by
        simpa only [String.toUTF8, String.toByteArray_append] using
          (ByteArray.append_assoc
            (a := pre.toUTF8)
            (b := (String.ofList [hexDigit digit]).toUTF8)
            (c := (hexNat w value ++ tail).toUTF8))
      have hpre_size :
          (pre ++ String.ofList [hexDigit digit]).toUTF8.size =
            pre.toUTF8.size + 1 := by
        have hchar_size' : (String.ofList [hexDigit digit]).toByteArray.size = 1 := by
          simpa [String.toUTF8] using hchar_size
        simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
        rw [hchar_size']
      rw [hbytes, hpre_size] at hread
      change (readHexDigit >>= fun d => readHexNat w (acc * 16 + d)).run
          {bytes := pre.toUTF8 ++ (hexNat (Nat.succ w) value ++ tail).toUTF8,
           offset := pre.toUTF8.size} = _
      rw [StateT.run_bind, hstep]
      rw [htail]
      have hhex : hexNat (Nat.succ w) value =
          String.ofList [hexDigit digit] ++ hexNat w value := by
        simp [hexNat, digit, base, hpow]
      have hhex_size : (hexNat (Nat.succ w) value).toUTF8.size =
          1 + (hexNat w value).toUTF8.size := by
        rw [hhex]
        simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
        have hchar_size' : (String.ofList [hexDigit digit]).toByteArray.size = 1 := by
          simpa [String.toUTF8] using hchar_size
        rw [hchar_size']
      rw [hhex_size]
      have harith := hexNat_arith w value acc
      rw [hexNat_arith w value acc] at hread
      simpa [hpow, htail, String.toUTF8, String.toByteArray_append,
        ByteArray.data_append, Array.append_assoc, hchar_size, Nat.add_assoc]
        using hread

theorem hexNat_size (w value : Nat) : (hexNat w value).toUTF8.size = w := by
  induction w with
  | zero => simp [hexNat]
  | succ w ih =>
      let base := 16 ^ w
      let digit := (value / base) % 16
      have hbase : 0 < base := by
        dsimp [base]
        exact Nat.pow_pos (by decide)
      have hdigit : digit < 16 := by
        dsimp [digit]
        exact Nat.mod_lt _ (by omega)
      have hpow : 2 ^ (w * 4) = base := by
        dsimp [base]
        rw [Nat.mul_comm, Nat.pow_mul]
      have hsplit : hexNat (Nat.succ w) value =
          String.ofList [hexDigit digit] ++ hexNat w value := by
        simp [hexNat, digit, base, hpow]
      have hchar : (hexDigit digit).toNat =
          if digit < 10 then 48 + digit else 87 + digit :=
        hexDigit_nat digit hdigit
      have hchar_size : (String.ofList [hexDigit digit]).toUTF8.size = 1 := by
        have hsmall : (hexDigit digit).toNat ≤ 127 := by
          rw [hchar]
          split <;> omega
        simp [String.ofList, List.utf8Encode, String.utf8EncodeChar, hsmall]
      rw [hsplit]
      have hchar_size' : (String.ofList [hexDigit digit]).toByteArray.size = 1 := by
        simpa [String.toUTF8] using hchar_size
      have ih' : (hexNat w value).toByteArray.size = w := by
        simpa [String.toUTF8] using ih
      simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
      rw [hchar_size', ih']
      omega

def IsI32 (value : Int) : Prop :=
  -2147483648 ≤ value ∧ value ≤ 2147483647

theorem wordNat_nonneg (value : Int) (h : 0 ≤ value) (hi : value ≤ 2147483647) :
    (Int.ofNat (wordNat value) : Int) = value := by
  have hmod : value % 4294967296 = value :=
    Int.emod_eq_of_lt h (by omega)
  have hto : (Int.ofNat (Int.toNat (value % 4294967296)) : Int) =
      value % 4294967296 := Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))
  change (Int.ofNat (Int.toNat (value % 4294967296)) : Int) = value
  exact hto.trans hmod

theorem wordNat_neg (value : Int) (hlo : -2147483648 ≤ value) (hhi : value < 0) :
    (Int.ofNat (wordNat value) : Int) = value + 4294967296 := by
  have hlow : 0 ≤ value + 4294967296 := by omega
  have hhigh : value + 4294967296 < 4294967296 := by omega
  have hshift : value % 4294967296 = value + 4294967296 := by
    have hs := Int.emod_eq_of_lt hlow hhigh
    have ha := Int.add_emod value 4294967296 4294967296
    have he : (value + 4294967296) % 4294967296 = value % 4294967296 := by
      rw [Int.add_emod]
      simp
    exact he.symm.trans hs
  have hto : (Int.ofNat (Int.toNat (value % 4294967296)) : Int) =
      value % 4294967296 := Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))
  change (Int.ofNat (Int.toNat (value % 4294967296)) : Int) = value + 4294967296
  exact hto.trans hshift

theorem signedWord_inverse (value : Int) (h : IsI32 value) :
    (if wordNat value < 2147483648 then
      (Int.ofNat (wordNat value))
    else
      (Int.ofNat (wordNat value) - 4294967296)) = value := by
  rcases h with ⟨hloI, hhiI⟩
  by_cases hnonneg : 0 ≤ value
  · have hw := wordNat_nonneg value hnonneg hhiI
    have hlt : wordNat value < 2147483648 := by
      have hi : (Int.ofNat (wordNat value) : Int) < 2147483648 := by
        calc
          (Int.ofNat (wordNat value) : Int) = value := hw
          _ < 2147483648 := by omega
      exact (Int.ofNat_lt).mp hi
    rw [if_pos hlt, hw]
  · have hzero : value = 0 ∨ value < 0 := by omega
    rcases hzero with rfl | hlt
    · simp [wordNat]
    · have hw := wordNat_neg value hloI hlt
      have hlo : 2147483648 ≤ wordNat value := by
        have hi : (2147483648 : Int) ≤ Int.ofNat (wordNat value) := by
          calc
            (2147483648 : Int) ≤ value + 4294967296 := by omega
            _ = Int.ofNat (wordNat value) := hw.symm
        exact (Int.ofNat_le).mp hi
      rw [if_neg (by omega), hw]
      omega

theorem readSignedWord_hexWord (pre tail : String) (value : Int) (h : IsI32 value) :
    (CertificateDecode.readSignedWord.run
      {bytes := pre.toUTF8 ++ (hexWord value ++ tail).toUTF8,
       offset := pre.toUTF8.size}) =
      some (value,
        {bytes := pre.toUTF8 ++ (hexWord value ++ tail).toUTF8,
         offset := pre.toUTF8.size + 8}) := by
  have hb := h
  rcases hb with ⟨hlo, hhi⟩
  unfold CertificateDecode.readSignedWord
  rw [StateT.run_bind]
  have hread := hexNat_read 8 (wordNat value) 0 pre tail
  rw [show hexWord value = hexNat 8 (wordNat value) by rfl]
  rw [hexNat_size] at hread
  rw [hread]
  have hword_lt : wordNat value < 4294967296 := by
    by_cases hnonneg : 0 ≤ value
    · have hw := wordNat_nonneg value hnonneg hhi
      have hi : (Int.ofNat (wordNat value) : Int) < 4294967296 := by
        calc
          (Int.ofNat (wordNat value) : Int) = value := hw
          _ < 4294967296 := by omega
      exact (Int.ofNat_lt).mp hi
    · have hlt : value < 0 := by omega
      have hw := wordNat_neg value hlo hlt
      have hi : (Int.ofNat (wordNat value) : Int) < 4294967296 := by
        calc
          (Int.ofNat (wordNat value) : Int) = value + 4294967296 := hw
          _ < 4294967296 := by omega
      exact (Int.ofNat_lt).mp hi
  have hmod : wordNat value % 16^8 = wordNat value := by
    rw [show 16^8 = 4294967296 by decide]
    exact Nat.mod_eq_of_lt hword_lt
  by_cases hw : wordNat value < 2147483648
  · have hs : (Int.ofNat (wordNat value) : Int) = value := by
      have hs' := signedWord_inverse value h
      simpa [hw] using hs'
    simp [hmod, hw, StateT.run]
    change some ((Int.ofNat (wordNat value), _)) = _
    rw [hs]
  · have hs : (Int.ofNat (wordNat value) : Int) - 4294967296 = value := by
      have hs' := signedWord_inverse value h
      simpa [hw] using hs'
    simp [hmod, hw, StateT.run]
    change some ((Int.ofNat (wordNat value) - 4294967296, _)) = _
    rw [hs]

def join : List String → String
  | [] => ""
  | value :: values => value ++ join values

theorem mapM_range_shift (start count : Nat) (read : DecodeM α) :
    List.mapM (fun _ : Nat => read) (List.range' start count) =
      List.mapM (fun _ : Nat => read) (List.range' (start + 1) count) := by
  induction count generalizing start with
  | zero => simp
  | succ count ih =>
      simp only [List.range'_succ]
      rw [List.mapM_cons, List.mapM_cons, ih (start + 1)]

theorem readMany_succ (count : Nat) (read : DecodeM α) (s : DecodeState) :
  (readMany (count+1) read).run s =
  (do
    let x ← read
    let xs ← readMany count read
    pure (x :: xs)).run s := by
  simp [readMany, List.range'_succ, StateT.run]
  rw [mapM_range_shift 0 count read]

theorem readMany_signed (values : List Int) (pre tail : String)
    (hvals : ∀ value ∈ values, IsI32 value) :
    (readMany values.length CertificateDecode.readSignedWord).run
      {bytes := pre.toUTF8 ++ (join (values.map hexWord) ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (values,
        {bytes := pre.toUTF8 ++ (join (values.map hexWord) ++ tail).toUTF8,
         offset := pre.toUTF8.size + (join (values.map hexWord)).toUTF8.size}) := by
  induction values generalizing pre with
  | nil => simp [readMany, join]
  | cons value values ih =>
      have hv := hvals value (by simp)
      have hrest : ∀ x ∈ values, IsI32 x := by
        intro x hx
        exact hvals x (by simp [hx])
      rw [show (value :: values).length = values.length + 1 by simp]
      rw [readMany_succ]
      rw [StateT.run_bind]
      have hone := readSignedWord_hexWord pre
        (join (values.map hexWord) ++ tail) value hv
      rw [show join ((value :: values).map hexWord) =
        hexWord value ++ join (values.map hexWord) by rfl]
      simp only [String.append_assoc]
      rw [hone]
      have htail := ih (pre ++ hexWord value) hrest
      have hbytes :
          (pre ++ hexWord value).toUTF8 ++
              (join (values.map hexWord) ++ tail).toUTF8 =
            pre.toUTF8 ++ (hexWord value ++
              (join (values.map hexWord) ++ tail)).toUTF8 := by
        simpa only [String.toUTF8, String.toByteArray_append] using
          (ByteArray.append_assoc (a := pre.toUTF8)
            (b := (hexWord value).toUTF8)
            (c := (join (values.map hexWord) ++ tail).toUTF8))
      have hsize : (hexWord value).toUTF8.size = 8 := by
        exact hexNat_size 8 (wordNat value)
      have hsize' : (hexWord value).toByteArray.size = 8 := by
        simpa [String.toUTF8] using hsize
      have hpre_size : (pre ++ hexWord value).toUTF8.size =
          pre.toUTF8.size + 8 := by
        simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
        rw [hsize']
      rw [hbytes, hpre_size] at htail
      simpa [join, hsize, hsize', String.toUTF8, String.toByteArray_append,
        ByteArray.data_append, Array.append_assoc, Nat.add_assoc] using htail

def hexByte (value : UInt8) : String := hexNat 2 value.toNat

theorem readByte_hexByte (pre tail : String) (byte : UInt8) :
    (readByte.run
      {bytes := pre.toUTF8 ++ (hexByte byte ++ tail).toUTF8,
       offset := pre.toUTF8.size}) =
      some (byte,
        {bytes := pre.toUTF8 ++ (hexByte byte ++ tail).toUTF8,
         offset := pre.toUTF8.size + 2}) := by
  unfold readByte
  rw [StateT.run_bind]
  have h := hexNat_read 2 byte.toNat 0 pre tail
  rw [show hexByte byte = hexNat 2 byte.toNat by rfl]
  rw [hexNat_size] at h
  rw [h]
  simp [UInt8.ofNat]
  exact UInt8.ofNat_toNat

def pushBytes : ByteArray → List UInt8 → ByteArray
  | buffer, [] => buffer
  | buffer, byte :: bytes => pushBytes (buffer.push byte) bytes

theorem byteArray_toList_data (bs : ByteArray) :
    bs.toList = bs.data.toList := by
  unfold ByteArray.toList
  have loop_eq : ∀ (i : Nat) (r : List UInt8),
      ByteArray.toList.loop bs i r =
        r.reverse ++ bs.data.toList.drop i := by
    intro i r
    fun_induction ByteArray.toList.loop bs i r with
    | case1 i r hi ih =>
        rw [ih]
        have hlen : i < bs.data.toList.length := by
          simpa [ByteArray.size_data] using hi
        have hdrop := List.drop_eq_getElem_cons hlen
        have hget : bs.get! i = bs.data.toList[i]'(by omega) := by
          have hget0 : bs.get! i = bs[i] := by
            cases bs with
            | mk data =>
                change i < data.size at hi
                unfold ByteArray.get!
                exact getElem!_pos data i hi
          rw [hget0]
          symm
          exact Array.getElem_toList (by simpa [ByteArray.size_data] using hi)
        rw [hdrop, hget]
        simp [List.reverse_cons, List.append_assoc]
    | case2 i r hi =>
        have hle : bs.data.toList.length ≤ i := by
          simpa [ByteArray.size_data] using hi
        rw [List.drop_eq_nil_of_le hle]
        simp
  exact loop_eq 0 []

theorem byteArray_toList_push (bs : ByteArray) (b : UInt8) :
    (bs.push b).toList = bs.toList ++ [b] := by
  rw [byteArray_toList_data, byteArray_toList_data]
  rw [ByteArray.data_push, Array.toList_push]

theorem pushBytes_toList (buffer : ByteArray) (values : List UInt8) :
    (pushBytes buffer values).toList = buffer.toList ++ values := by
  induction values generalizing buffer with
  | nil => simp [pushBytes]
  | cons value values ih =>
      rw [pushBytes, ih, byteArray_toList_push]
      simp [List.append_assoc]

theorem ensureRemaining_exact (needed : Nat) (state : DecodeState)
    (h : needed ≤ state.bytes.size - state.offset) :
    (ensureRemaining needed).run state = some ((), state) := by
  unfold ensureRemaining
  rw [StateT.run_bind, StateT.run_get]
  simp [h]

theorem join_hex_size (values : List UInt8) :
    (join (values.map hexByte)).toUTF8.size = 2 * values.length := by
  induction values with
  | nil => simp [join]
  | cons value values ih =>
      have hs : (hexByte value).toUTF8.size = 2 := hexNat_size 2 value.toNat
      have hs' : (hexByte value).toByteArray.size = 2 := by
        simpa [String.toUTF8] using hs
      have ih' : (join (values.map hexByte)).toByteArray.size = 2 * values.length := by
        simpa [String.toUTF8] using ih
      simp only [List.map, join, String.toUTF8, String.toByteArray_append,
        ByteArray.size_append]
      rw [hs', ih']
      simp only [List.length_cons]
      omega

theorem foldBytes (start : Nat) (values : List UInt8) (buffer : ByteArray)
    (pre tail : String) :
    (List.foldlM (fun b _ => b.push <$> readByte) buffer
      (List.range' start values.length)).run
      {bytes := pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (pushBytes buffer values,
        {bytes := pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8,
         offset := pre.toUTF8.size + (join (values.map hexByte)).toUTF8.size}) := by
  induction values generalizing start buffer pre with
  | nil => simp [pushBytes, join]
  | cons value values ih =>
      rw [show (value :: values).length = values.length + 1 by simp]
      rw [List.range'_succ, List.foldlM_cons]
      rw [show join ((value :: values).map hexByte) =
        hexByte value ++ join (values.map hexByte) by rfl]
      simp only [String.append_assoc]
      rw [StateT.run_bind]
      change ((buffer.push <$> readByte).run _).bind _ = _
      rw [StateT.run_map]
      have hone := readByte_hexByte pre
        (join (values.map hexByte) ++ tail) value
      rw [hone]
      have htail := ih (start + 1) (buffer.push value) (pre ++ hexByte value)
      have hbytes :
          (pre ++ hexByte value).toUTF8 ++
              (join (values.map hexByte) ++ tail).toUTF8 =
            pre.toUTF8 ++ (hexByte value ++
              (join (values.map hexByte) ++ tail)).toUTF8 := by
        simpa only [String.toUTF8, String.toByteArray_append] using
          (ByteArray.append_assoc (a := pre.toUTF8)
            (b := (hexByte value).toUTF8)
            (c := (join (values.map hexByte) ++ tail).toUTF8))
      have hs : (hexByte value).toUTF8.size = 2 := hexNat_size 2 value.toNat
      have hs' : (hexByte value).toByteArray.size = 2 := by
        simpa [String.toUTF8] using hs
      have hpre_size : (pre ++ hexByte value).toUTF8.size =
          pre.toUTF8.size + 2 := by
        simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
        rw [hs']
      rw [hbytes, hpre_size] at htail
      simpa [pushBytes, join, hs, hs', String.toUTF8,
        String.toByteArray_append, ByteArray.data_append, Array.append_assoc,
        Nat.add_assoc] using htail

theorem readBytes_hex (values : List UInt8) (pre tail : String) :
    (readBytes values.length).run
      {bytes := pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (pushBytes ByteArray.empty values,
        {bytes := pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8,
         offset := pre.toUTF8.size + (join (values.map hexByte)).toUTF8.size}) := by
  have hsize := join_hex_size values
  have hsize' : (join (values.map hexByte)).toByteArray.size = 2 * values.length := by
    simpa [String.toUTF8] using hsize
  unfold readBytes
  have hcond : values.length * 2 ≤
      (pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8).size - pre.toUTF8.size := by
    simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
    rw [hsize']
    omega
  have hcond2 : values.length * 2 ≤
      (join (values.map hexByte)).toUTF8.size + tail.toUTF8.size := by
    rw [hsize]
    omega
  rw [StateT.run_bind]
  have hensure := ensureRemaining_exact (values.length * 2)
    {bytes := pre.toUTF8 ++ (join (values.map hexByte) ++ tail).toUTF8,
     offset := pre.toUTF8.size} hcond
  rw [hensure]
  simp
  exact foldBytes 0 values ByteArray.empty pre tail

theorem raw_extract (pre payload tail : String) :
    (pre.toUTF8 ++ (payload ++ tail).toUTF8).extract pre.toUTF8.size
      (pre.toUTF8.size + payload.toUTF8.size) = payload.toUTF8 := by
  rw [ByteArray.extract_append]
  simp only [Nat.sub_self, Nat.add_sub_cancel_left]
  simp only [String.toUTF8, String.toByteArray_append]
  rw [ByteArray.extract_append]
  apply ByteArray.ext
  simp [ByteArray.extract, ByteArray.copySlice,
    Array.extract_empty_of_size_le_start]

theorem readRawBytes_hex (payload : String) (pre tail : String) :
    (readRawBytes payload.toUTF8.size).run
      {bytes := pre.toUTF8 ++ (payload ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (payload.toUTF8,
        {bytes := pre.toUTF8 ++ (payload ++ tail).toUTF8,
         offset := pre.toUTF8.size + payload.toUTF8.size}) := by
  have hcond : payload.toUTF8.size ≤
      (pre.toUTF8 ++ (payload ++ tail).toUTF8).size - pre.toUTF8.size := by
    simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
    omega
  unfold readRawBytes
  rw [StateT.run_bind]
  have hensure := ensureRemaining_exact payload.toUTF8.size
    {bytes := pre.toUTF8 ++ (payload ++ tail).toUTF8,
     offset := pre.toUTF8.size} hcond
  rw [hensure]
  change StateT.run ((get : DecodeM DecodeState) >>= fun current =>
    (fun a => current.bytes.extract current.offset (current.offset + payload.toUTF8.size)) <$>
      set { current with offset := current.offset + payload.toUTF8.size }) _ = _
  rw [StateT.run_bind, StateT.run_get]
  change StateT.run
    ((fun _ : PUnit =>
      (pre.toUTF8 ++ (payload ++ tail).toUTF8).extract pre.toUTF8.size
        (pre.toUTF8.size + payload.toUTF8.size)) <$>
      (set (σ := DecodeState) (m := StateT DecodeState Option)
        { bytes := pre.toUTF8 ++ (payload ++ tail).toUTF8,
          offset := pre.toUTF8.size + payload.toUTF8.size } : DecodeM PUnit))
    { bytes := pre.toUTF8 ++ (payload ++ tail).toUTF8,
      offset := pre.toUTF8.size } = _
  rw [StateT.run_map, StateT.run_set]
  simp
  simpa [String.toUTF8, String.toByteArray_append] using
    raw_extract pre payload tail

def hexFunction (span : FunctionSpan) : String :=
  hexNat 8 span.start ++ hexNat 8 span.length

def IsU32 (value : Nat) : Prop := value < 4294967296

theorem readU32_hexNat (pre tail : String) (value : Nat) (h : IsU32 value) :
    (readU32.run
      {bytes := pre.toUTF8 ++ (hexNat 8 value ++ tail).toUTF8,
       offset := pre.toUTF8.size}) =
      some (value,
        {bytes := pre.toUTF8 ++ (hexNat 8 value ++ tail).toUTF8,
         offset := pre.toUTF8.size + 8}) := by
  unfold readU32
  have hread := hexNat_read 8 value 0 pre tail
  rw [hread, hexNat_size]
  have hmod : value % 16^8 = value := by
    rw [show 16^8 = 4294967296 by decide]
    exact Nat.mod_eq_of_lt h
  simp [hmod]

def readFunction : DecodeM FunctionSpan := do
  let start ← readU32
  let length ← readU32
  pure {start, length}

theorem readFunction_hexFunction (pre tail : String) (span : FunctionSpan)
    (hs : IsU32 span.start) (hl : IsU32 span.length) :
    (readFunction.run
      {bytes := pre.toUTF8 ++ (hexFunction span ++ tail).toUTF8,
       offset := pre.toUTF8.size}) =
      some (span,
        {bytes := pre.toUTF8 ++ (hexFunction span ++ tail).toUTF8,
         offset := pre.toUTF8.size + 16}) := by
  unfold readFunction
  rw [show hexFunction span = hexNat 8 span.start ++ hexNat 8 span.length by rfl]
  simp only [String.append_assoc]
  rw [StateT.run_bind]
  have hstart := readU32_hexNat pre
    (hexNat 8 span.length ++ tail) span.start hs
  rw [hstart]
  simp
  refine ⟨span.length, ?_, rfl⟩
  have hlength := readU32_hexNat (pre ++ hexNat 8 span.start) tail span.length hl
  have hbytes :
      (pre ++ hexNat 8 span.start).toUTF8 ++ (hexNat 8 span.length ++ tail).toUTF8 =
        pre.toUTF8 ++ (hexNat 8 span.start ++
          (hexNat 8 span.length ++ tail)).toUTF8 := by
    simpa only [String.toUTF8, String.toByteArray_append] using
      (ByteArray.append_assoc (a := pre.toUTF8)
        (b := (hexNat 8 span.start).toUTF8)
        (c := (hexNat 8 span.length ++ tail).toUTF8))
  have hsize : (hexNat 8 span.start).toUTF8.size = 8 := hexNat_size 8 span.start
  have hsize' : (hexNat 8 span.start).toByteArray.size = 8 := by
    simpa [String.toUTF8] using hsize
  have hpre_size : (pre ++ hexNat 8 span.start).toUTF8.size =
      pre.toUTF8.size + 8 := by
    simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
    rw [hsize']
  rw [hbytes, hpre_size] at hlength
  simpa [StateT.run, hbytes, hsize, hsize', String.toUTF8,
    String.toByteArray_append, ByteArray.data_append, Array.append_assoc,
    Nat.add_assoc] using hlength

theorem readMany_functions (values : List FunctionSpan) (pre tail : String)
    (hvals : ∀ span ∈ values, IsU32 span.start ∧ IsU32 span.length) :
    (readMany values.length readFunction).run
      {bytes := pre.toUTF8 ++ (join (values.map hexFunction) ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (values,
        {bytes := pre.toUTF8 ++ (join (values.map hexFunction) ++ tail).toUTF8,
         offset := pre.toUTF8.size + (join (values.map hexFunction)).toUTF8.size}) := by
  induction values generalizing pre with
  | nil => simp [readMany, join]
  | cons value values ih =>
      have hv := hvals value (by simp)
      have hrest : ∀ x ∈ values, IsU32 x.start ∧ IsU32 x.length := by
        intro x hx
        exact hvals x (by simp [hx])
      rw [show (value :: values).length = values.length + 1 by simp]
      rw [readMany_succ, StateT.run_bind]
      have hone := readFunction_hexFunction pre
        (join (values.map hexFunction) ++ tail) value hv.1 hv.2
      rw [show join ((value :: values).map hexFunction) =
        hexFunction value ++ join (values.map hexFunction) by rfl]
      simp only [String.append_assoc]
      rw [hone]
      have htail := ih (pre ++ hexFunction value) hrest
      have hbytes :
          (pre ++ hexFunction value).toUTF8 ++
              (join (values.map hexFunction) ++ tail).toUTF8 =
            pre.toUTF8 ++ (hexFunction value ++
              (join (values.map hexFunction) ++ tail)).toUTF8 := by
        simpa only [String.toUTF8, String.toByteArray_append] using
          (ByteArray.append_assoc (a := pre.toUTF8)
            (b := (hexFunction value).toUTF8)
            (c := (join (values.map hexFunction) ++ tail).toUTF8))
      have hsize : (hexFunction value).toUTF8.size = 16 := by
        simp only [hexFunction, String.toUTF8, String.toByteArray_append,
          ByteArray.size_append]
        have hs : (hexNat 8 value.start).toByteArray.size = 8 := by
          simpa [String.toUTF8] using hexNat_size 8 value.start
        have hl : (hexNat 8 value.length).toByteArray.size = 8 := by
          simpa [String.toUTF8] using hexNat_size 8 value.length
        rw [hs, hl]
      have hsize' : (hexFunction value).toByteArray.size = 16 := by
        simpa [String.toUTF8] using hsize
      have hpre_size : (pre ++ hexFunction value).toUTF8.size =
          pre.toUTF8.size + 16 := by
        simp only [String.toUTF8, String.toByteArray_append, ByteArray.size_append]
        rw [hsize']
      rw [hbytes, hpre_size] at htail
      simpa [join, hsize, hsize', String.toUTF8, String.toByteArray_append,
        ByteArray.data_append, Array.append_assoc, Nat.add_assoc] using htail

theorem readMany_functions_inline (values : List FunctionSpan) (pre tail : String)
    (hvals : ∀ span ∈ values, IsU32 span.start ∧ IsU32 span.length) :
    (readMany values.length (do
      let start ← readU32
      let length ← readU32
      pure {start, length})).run
      {bytes := pre.toUTF8 ++ (join (values.map hexFunction) ++ tail).toUTF8,
       offset := pre.toUTF8.size} =
      some (values,
        {bytes := pre.toUTF8 ++ (join (values.map hexFunction) ++ tail).toUTF8,
         offset := pre.toUTF8.size + (join (values.map hexFunction)).toUTF8.size}) := by
  simpa [readFunction] using readMany_functions values pre tail hvals

def encodeCertificate (certificate : Certificate) : String :=
  hexNat 8 3 ++
  hexNat 8 certificate.compact.toUTF8.size ++
  certificate.compact ++
  hexNat 8 certificate.transport.length ++
  join (certificate.transport.map hexWord) ++
  hexNat 8 certificate.elf.length ++
  join (certificate.elf.map hexByte) ++
  hexNat 8 certificate.functions.length ++
  join (certificate.functions.map hexFunction)

def Representable (certificate : Certificate) : Prop :=
    certificate.compact.toUTF8.size < 4294967296 ∧
    String.fromUTF8? certificate.compact.toUTF8 = some certificate.compact ∧
    certificate.transport.length < 4294967296 ∧
  certificate.elf.length < 4294967296 ∧
  certificate.functions.length < 4294967296 ∧
  (∀ value ∈ certificate.transport, IsI32 value) ∧
  (∀ span ∈ certificate.functions, IsU32 span.start ∧ IsU32 span.length)

theorem readCertificate_roundtrip_state (certificate : Certificate)
    (h : Representable certificate) :
    (CertificateDecode.readCertificate.run
      {bytes := (encodeCertificate certificate).toUTF8, offset := 0}) =
      some (certificate,
        {bytes := (encodeCertificate certificate).toUTF8,
         offset := (encodeCertificate certificate).toUTF8.size}) := by
  rcases h with ⟨hcompact, hcompactUtf8, htransport, helf, hfunctions, hi32, hspan⟩
  unfold CertificateDecode.readCertificate
  rw [StateT.run_bind]
  have hv := readU32_hexNat ""
    (hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction)) 3 (by
        change 3 < 4294967296
        omega)
  rw [show encodeCertificate certificate =
    hexNat 8 3 ++
      (hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction)) by
        simp [encodeCertificate, String.append_assoc]]
  simp only [String.append_assoc]
  have hv0 :
      (readU32.run
        {bytes := (hexNat 8 3 ++
          (hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
          hexNat 8 certificate.transport.length ++
          join (certificate.transport.map hexWord) ++
          hexNat 8 certificate.elf.length ++
          join (certificate.elf.map hexByte) ++
          hexNat 8 certificate.functions.length ++
          join (certificate.functions.map hexFunction))).toUTF8,
         offset := 0}) =
        some (3,
          {bytes := (hexNat 8 3 ++
            (hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
            hexNat 8 certificate.transport.length ++
            join (certificate.transport.map hexWord) ++
            hexNat 8 certificate.elf.length ++
            join (certificate.elf.map hexByte) ++
            hexNat 8 certificate.functions.length ++
            join (certificate.functions.map hexFunction))).toUTF8,
           offset := 8}) := by
    simpa [String.toUTF8] using hv
  simp only [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at hv0 ⊢
  rw [hv0]
  simp
  have hcompactLen := readU32_hexNat (hexNat 8 3)
    (certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction))
    certificate.compact.toUTF8.size hcompact
  have hcompactLen' := hcompactLen
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at hcompactLen'
  have h3 : (hexNat 8 3).utf8ByteSize = 8 := by
    exact hexNat_size 8 3
  rw [h3] at hcompactLen'
  rw [hcompactLen']
  simp
  have hraw := readRawBytes_hex certificate.compact
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size)
    (hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction))
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at hraw
  have hclsize : (hexNat 8 certificate.compact.toUTF8.size).utf8ByteSize = 8 := by
    exact hexNat_size 8 certificate.compact.toUTF8.size
  have hclsize' : (hexNat 8 certificate.compact.utf8ByteSize).utf8ByteSize = 8 := by
    exact hexNat_size 8 certificate.compact.utf8ByteSize
  rw [h3, hclsize'] at hraw
  rw [hraw]
  have hdecode : String.fromUTF8? certificate.compact.toByteArray =
      some certificate.compact := by
    simpa [String.toUTF8] using hcompactUtf8
  simp [hdecode]
  have hcount := readU32_hexNat
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact)
    (join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction))
    certificate.transport.length htransport
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc,
    Nat.add_assoc] at hcount
  rw [h3, hclsize'] at hcount
  have hoff : 8 + (8 + certificate.compact.utf8ByteSize) =
      16 + certificate.compact.utf8ByteSize := by omega
  rw [hoff] at hcount
  rw [hcount]
  simp
  have htransport' := readMany_signed certificate.transport
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length)
    (hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction)) hi32
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at htransport'
  rw [h3, hclsize'] at htransport'
  have hcountsize : (hexNat 8 certificate.transport.length).utf8ByteSize = 8 := by
    exact hexNat_size 8 certificate.transport.length
  rw [hcountsize] at htransport'
  rw [htransport']
  simp
  have helfLen := readU32_hexNat
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord))
    (join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction))
    certificate.elf.length helf
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at helfLen
  rw [h3, hclsize', hcountsize] at helfLen
  have hoffElf :
      8 + (8 + (certificate.compact.utf8ByteSize + 8)) +
          (join (certificate.transport.map hexWord)).utf8ByteSize =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + (join (certificate.transport.map hexWord)).utf8ByteSize))) := by omega
  rw [← hoffElf] at helfLen
  rw [helfLen]
  simp
  have helfBytes := readBytes_hex certificate.elf
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length)
    (hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction))
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at helfBytes
  rw [h3, hclsize', hcountsize] at helfBytes
  have helfCountSize : (hexNat 8 certificate.elf.length).utf8ByteSize = 8 := by
    exact hexNat_size 8 certificate.elf.length
  rw [helfCountSize] at helfBytes
  have hoffBytes :
      8 + (8 + (certificate.compact.utf8ByteSize + 8)) +
          (join (certificate.transport.map hexWord)).utf8ByteSize + 8 =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + ((join (certificate.transport.map hexWord)).utf8ByteSize + 8)))) := by omega
  rw [← hoffBytes] at helfBytes
  rw [helfBytes]
  simp
  have hfunCount := readU32_hexNat
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte))
    (join (certificate.functions.map hexFunction))
    certificate.functions.length hfunctions
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at hfunCount
  rw [h3, hclsize', hcountsize, helfCountSize] at hfunCount
  have hoffFun :
      8 + (8 + (certificate.compact.utf8ByteSize + 8)) +
          (join (certificate.transport.map hexWord)).utf8ByteSize + 8 +
          (join (certificate.elf.map hexByte)).utf8ByteSize =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + ((join (certificate.transport.map hexWord)).utf8ByteSize +
            (8 + (join (certificate.elf.map hexByte)).utf8ByteSize))))) := by omega
  rw [← hoffFun] at hfunCount
  rw [hfunCount]
  simp
  have hfunRows := readMany_functions_inline certificate.functions
    (hexNat 8 3 ++ hexNat 8 certificate.compact.toUTF8.size ++ certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length)
    "" hspan
  simp [String.toUTF8, String.toByteArray_append, ByteArray.append_assoc] at hfunRows
  have hfunCountSize : (hexNat 8 certificate.functions.length).utf8ByteSize = 8 := by
    exact hexNat_size 8 certificate.functions.length
  rw [h3, hclsize', hcountsize, helfCountSize, hfunCountSize] at hfunRows
  have hoffRows :
      8 + (8 + (certificate.compact.utf8ByteSize + 8)) +
          (join (certificate.transport.map hexWord)).utf8ByteSize + 8 +
          (join (certificate.elf.map hexByte)).utf8ByteSize + 8 =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + ((join (certificate.transport.map hexWord)).utf8ByteSize +
            (8 + ((join (certificate.elf.map hexByte)).utf8ByteSize + 8)))))) := by omega
  rw [← hoffRows] at hfunRows
  rw [hfunRows]
  simp only [Option.bind_some]
  rw [h3, hclsize', hcountsize, helfCountSize, hfunCountSize]
  have hfinal :
      8 + (8 + (certificate.compact.utf8ByteSize + 8)) +
          (join (certificate.transport.map hexWord)).utf8ByteSize + 8 +
          (join (certificate.elf.map hexByte)).utf8ByteSize + 8 +
          (join (certificate.functions.map hexFunction)).utf8ByteSize =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + ((join (certificate.transport.map hexWord)).utf8ByteSize +
              (8 + ((join (certificate.elf.map hexByte)).utf8ByteSize +
                  (8 + (join (certificate.functions.map hexFunction)).utf8ByteSize))))))) := by omega
  have hbytesSize :
      ByteArray.size
        ((hexNat 8 3).toByteArray ++
          ((hexNat 8 certificate.compact.utf8ByteSize).toByteArray ++
            (certificate.compact.toByteArray ++
              ((hexNat 8 certificate.transport.length).toByteArray ++
                ((join (certificate.transport.map hexWord)).toByteArray ++
                  ((hexNat 8 certificate.elf.length).toByteArray ++
                    ((join (certificate.elf.map hexByte)).toByteArray ++
                      ((hexNat 8 certificate.functions.length).toByteArray ++
                        (join (certificate.functions.map hexFunction)).toByteArray)))))))) =
        8 + (8 + (certificate.compact.utf8ByteSize +
          (8 + ((join (certificate.transport.map hexWord)).utf8ByteSize +
            (8 + ((join (certificate.elf.map hexByte)).utf8ByteSize +
              (8 + (join (certificate.functions.map hexFunction)).utf8ByteSize))))))) := by
    simp [ByteArray.size_append, h3, hclsize', hcountsize,
      helfCountSize, hfunCountSize]
  rw [hbytesSize]
  rw [if_pos hfinal]
  have hpure {α : Type} (value : α) (state : DecodeState) :
      StateT.run (pure value : DecodeM α) state = some (value, state) := by
    rfl
  rw [hpure]
  simp [pushBytes_toList]
  omega

theorem decodeCertificate_roundtrip (certificate : Certificate)
    (h : Representable certificate) :
    decodeCertificate? (encodeCertificate certificate) = some certificate := by
  unfold decodeCertificate?
  rw [readCertificate_roundtrip_state certificate h]
  rfl

def fixture : Certificate := {
  compact := "00000000"
  transport := [-1, 42]
  elf := [0, 255]
  functions := [{ start := 1, length := 2 }]
}

example : Representable fixture := by
  simp only [Representable, fixture]
  refine ⟨by decide, ?_, by decide, by decide, by decide, ?_, ?_⟩
  · rfl
  · intro value hv
    simp [IsI32] at hv ⊢
    omega
  · intro span hs
    simp at hs
    rcases hs with rfl
    change 1 < 4294967296 ∧ 2 < 4294967296
    decide

example : decodeCertificate? (encodeCertificate fixture) = some fixture := by
  apply decodeCertificate_roundtrip fixture
  simp only [Representable, fixture]
  refine ⟨by decide, ?_, by decide, by decide, by decide, ?_, ?_⟩
  · rfl
  · intro value hv
    simp [IsI32] at hv ⊢
    omega
  · intro span hs
    simp at hs
    rcases hs with rfl
    change 1 < 4294967296 ∧ 2 < 4294967296
    decide

#eval decodeCertificate? (encodeCertificate fixture)

theorem encodeCertificate_parts (certificate : Certificate) :
    encodeCertificate certificate =
      hexNat 8 3 ++
      hexNat 8 certificate.compact.toUTF8.size ++
      certificate.compact ++
      hexNat 8 certificate.transport.length ++
      join (certificate.transport.map hexWord) ++
      hexNat 8 certificate.elf.length ++
      join (certificate.elf.map hexByte) ++
      hexNat 8 certificate.functions.length ++
      join (certificate.functions.map hexFunction) := by
  rfl

example (n : Nat) (bounded : n < 16) :
    (readHexDigit.run
      { bytes := (String.ofList [hexDigit n]).toUTF8, offset := 0 }) =
      some (n, { bytes := (String.ofList [hexDigit n]).toUTF8, offset := 1 }) := by
  have cases : n = 0 ∨ n = 1 ∨ n = 2 ∨ n = 3 ∨
      n = 4 ∨ n = 5 ∨ n = 6 ∨ n = 7 ∨
      n = 8 ∨ n = 9 ∨ n = 10 ∨ n = 11 ∨
      n = 12 ∨ n = 13 ∨ n = 14 ∨ n = 15 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [readHexDigit, hexDigit, String.ofList, List.utf8Encode,
      String.utf8EncodeChar]

end Lanius.Extraction.CertificateRoundTrip
