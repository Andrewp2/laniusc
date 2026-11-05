import Lanius.Cert.Model

/-! # check_mini.lani's `check`, as Lean functions

Each function mirrors the one of the same name in formal/cert/check_mini.lani,
statement for statement, on `Int` words (`rd`); each `while` is a function
of a fuel argument and a loop variable, and running out of fuel is reject
code 99. The digest (`mix`, `hash_tree`) is left out: it changes no reject
code. `check fuel w` is 0 when the checker accepts `w`, else its code.

That Core's run of check_mini's `main` agrees with `check` is the open
statement `Lanius.Open.CertMainFaithful`; that `check` is sound is
`Lanius.Open.CertShallowSound`. -/

namespace Lanius.Cert

def STACK : Int := 16384

def sortOf (w : Words) (nodes cons n : Int) : Int :=
  let h := rd w (nodes + 3 * n)
  if h = VAR then rd w (nodes + 3 * n + 2) else rd w (cons + 3 * h)

/-- `matches`' loop: the stack as a list of (template, node) pairs, top first. -/
def matchLoop (w : Words) (nodes cons pool so nv : Int) : Nat → List (Int × Int) → Bool
  | 0, _ => false
  | _ + 1, [] => true
  | fuel + 1, (tt, xx) :: rest =>
    let h := rd w (nodes + 3 * tt)
    if h = VAR then
      let k := rd w (nodes + 3 * tt + 1)
      if k ≥ nv then false
      else if rd w (pool + so + k) ≠ xx then false
      else if sortOf w nodes cons xx ≠ rd w (nodes + 3 * tt + 2) then false
      else matchLoop w nodes cons pool so nv fuel rest
    else if rd w (nodes + 3 * xx) ≠ h then false
    else
      let ar := rd w (cons + 3 * h + 1)
      if 2 * (rest.length : Int) + 2 * ar > STACK then false
      else
        let ta := pool + rd w (nodes + 3 * tt + 1)
        let xa := pool + rd w (nodes + 3 * xx + 1)
        matchLoop w nodes cons pool so nv fuel
          (((List.range ar.toNat).map fun (i : Nat) => (rd w (ta + (i : Int)), rd w (xa + (i : Int)))).reverse ++ rest)

/-- Does template `t`, under the substitution at `pool[so..so+nv)`, give node `x`? -/
def matchTemplate (w : Words) (nodes cons pool t so nv x : Int) (fuel : Nat) : Bool :=
  matchLoop w nodes cons pool so nv fuel [(t, x)]

/-- `while (i < count) { if (w[i] < 0) reject 11 }`: the first negative word's code. -/
def negLoop (w : Words) (count : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, i => if i < count then (if rd w i < 0 then 11 else negLoop w count fuel (i + 1)) else 0

/-- The constructor table's loop (codes 20, 21). -/
def consArgLoop (w : Words) (oPool' ns ao ar : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, j => if j < ar then (if rd w (oPool' + ao + j) ≥ ns then 21 else consArgLoop w oPool' ns ao ar fuel (j + 1)) else 0

def consLoop (w : Words) (oCons' oPool' ns nc np : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, i =>
    if i < nc then
      let res := rd w (oCons' + 3 * i)
      let ar := rd w (oCons' + 3 * i + 1)
      let ao := rd w (oCons' + 3 * i + 2)
      if res ≥ ns ∨ ar > np ∨ ao > np - ar then 20
      else
        let c := consArgLoop w oPool' ns ao ar fuel 0
        if c ≠ 0 then c else consLoop w oCons' oPool' ns nc np fuel (i + 1)
    else 0

/-- The node table's argument loop (codes 33, 34). -/
def nodeArgLoop (w : Words) (oNodes' oCons' oPool' i a ao ar : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, j =>
    if j < ar then
      let x := rd w (oPool' + a + j)
      if x ≥ i then 33
      else if sortOf w oNodes' oCons' x ≠ rd w (oPool' + ao + j) then 34
      else nodeArgLoop w oNodes' oCons' oPool' i a ao ar fuel (j + 1)
    else 0

def nodeLoop (w : Words) (oNodes' oCons' oPool' ns nc nn np : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, i =>
    if i < nn then
      let h := rd w (oNodes' + 3 * i)
      let a := rd w (oNodes' + 3 * i + 1)
      if h = VAR then
        (if rd w (oNodes' + 3 * i + 2) ≥ ns then 30 else nodeLoop w oNodes' oCons' oPool' ns nc nn np fuel (i + 1))
      else if h ≥ nc then 31
      else
        let ar := rd w (oCons' + 3 * h + 1)
        let ao := rd w (oCons' + 3 * h + 2)
        if a > np - ar then 32
        else
          let c := nodeArgLoop w oNodes' oCons' oPool' i a ao ar fuel 0
          if c ≠ 0 then c else nodeLoop w oNodes' oCons' oPool' ns nc nn np fuel (i + 1)
    else 0

/-- The substitution's entries are nodes (code 54). -/
def substLoop (w : Words) (oPool' so nv nn : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, k => if k < nv then (if rd w (oPool' + so + k) ≥ nn then 54 else substLoop w oPool' so nv nn fuel (k + 1)) else 0

/-- Each premise is an earlier step of this theorem whose result is the rule's hypothesis (56, 57). -/
def premLoop (w : Words) (oNodes' oCons' oSteps' oPool' so nv po rho prevEnd s rnh : Int) (mfuel : Nat) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, k =>
    if k < rnh then
      let p := rd w (oPool' + po + k)
      if p < prevEnd ∨ p ≥ s then 56
      else if !matchTemplate w oNodes' oCons' oPool' (rd w (oPool' + rho + k)) so nv (rd w (oSteps' + 4 * p + 3)) mfuel then 57
      else premLoop w oNodes' oCons' oSteps' oPool' so nv po rho prevEnd s rnh mfuel fuel (k + 1)
    else 0

/-- `check_step`: 0 or a reject code for step `s` of theorem `r`. -/
def checkStep (w : Words) (oNodes' oCons' oRules' oSteps' oPool' nn np nh ho r prevEnd s : Int) (fuel : Nat) : Int :=
  let sb := oSteps' + 4 * s
  let rule := rd w sb
  let so := rd w (sb + 1)
  let po := rd w (sb + 2)
  let res := rd w (sb + 3)
  if res ≥ nn then 50
  else if rule = VAR then
    (if so ≥ nh ∨ rd w (oPool' + ho + so) ≠ res then 51 else 0)
  else if rule ≥ r then 52
  else
    let rb := oRules' + 6 * rule
    let nv := rd w (rb + 1)
    let rnh := rd w (rb + 2)
    let rho := rd w (rb + 3)
    if so > np - nv ∨ po > np - rnh then 53
    else
      let c := substLoop w oPool' so nv nn fuel 0
      if c ≠ 0 then c
      else if !matchTemplate w oNodes' oCons' oPool' (rd w (rb + 4)) so nv res fuel then 55
      else premLoop w oNodes' oCons' oSteps' oPool' so nv po rho prevEnd s rnh fuel fuel 0

/-- The steps of one theorem. -/
def stepLoop (w : Words) (oNodes' oCons' oRules' oSteps' oPool' nn np nh ho r prevEnd endS : Int) (cfuel : Nat) :
    Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, s =>
    if s < endS then
      let c := checkStep w oNodes' oCons' oRules' oSteps' oPool' nn np nh ho r prevEnd s cfuel
      if c ≠ 0 then c else stepLoop w oNodes' oCons' oRules' oSteps' oPool' nn np nh ho r prevEnd endS cfuel fuel (s + 1)
    else 0

/-- A rule's hypotheses are formula nodes (codes 42, 43). -/
def hypLoop (w : Words) (oSorts' oNodes' oCons' oPool' nn ho nh : Int) : Nat → Int → Int
  | 0, _ => 99
  | fuel + 1, j =>
    if j < nh then
      let hy := rd w (oPool' + ho + j)
      if hy ≥ nn then 42
      else if rd w (oSorts' + sortOf w oNodes' oCons' hy) ≠ 1 then 43
      else hypLoop w oSorts' oNodes' oCons' oPool' nn ho nh fuel (j + 1)
    else 0

/-- The rules, with `prevEnd` the end of the last theorem's steps; at the end
of the table, code 59 unless every step belongs to a theorem. -/
def ruleLoop (w : Words) (oSorts' oNodes' oCons' oRules' oSteps' oPool' nn nr nst np : Int) (cfuel : Nat) :
    Nat → Int → Int → Int
  | 0, _, _ => 99
  | fuel + 1, r, prevEnd =>
    if r < nr then
      let base := oRules' + 6 * r
      let k := rd w base
      let nh := rd w (base + 2)
      let ho := rd w (base + 3)
      let cl := rd w (base + 4)
      let endS := rd w (base + 5)
      if cl ≥ nn ∨ nh > np ∨ ho > np - nh then 40
      else if rd w (oSorts' + sortOf w oNodes' oCons' cl) ≠ 1 then 41
      else
        let c := hypLoop w oSorts' oNodes' oCons' oPool' nn ho nh cfuel 0
        if c ≠ 0 then c
        else if k = 0 then ruleLoop w oSorts' oNodes' oCons' oRules' oSteps' oPool' nn nr nst np cfuel fuel (r + 1) prevEnd
        else if k ≠ 1 ∨ endS ≤ prevEnd ∨ endS > nst then 44
        else
          let c := stepLoop w oNodes' oCons' oRules' oSteps' oPool' nn np nh ho r prevEnd endS cfuel cfuel prevEnd
          if c ≠ 0 then c
          else if rd w (oSteps' + 4 * (endS - 1) + 3) ≠ cl then 58
          else ruleLoop w oSorts' oNodes' oCons' oRules' oSteps' oPool' nn nr nst np cfuel fuel (r + 1) endS
    else if prevEnd ≠ nst then 59 else 0

/-- check_mini's `check(w, count, stack).code`, with `count` the number of words. -/
def check (fuel : Nat) (w : Words) : Int :=
  let count : Int := w.length
  if count < 8 then 10
  else
    let c := negLoop w count fuel 0
    if c ≠ 0 then c
    else if rd w 0 ≠ 1414677324 ∨ rd w 1 ≠ 1 then 12
    else
      let ns := rd w 2
      let nc := rd w 3
      let nn := rd w 4
      let nr := rd w 5
      let nst := rd w 6
      let np := rd w 7
      if ns > count ∨ nc > count / 3 ∨ nn > count / 3 ∨ nr > count / 6 ∨ nst > count / 4 ∨ np > count then 13
      else
        let oSorts' : Int := 8
        let oCons' := oSorts' + ns
        let oNodes' := oCons' + 3 * nc
        let oRules' := oNodes' + 3 * nn
        let oSteps' := oRules' + 6 * nr
        let oPool' := oSteps' + 4 * nst
        if oPool' + np ≠ count then 14
        else
          let c := consLoop w oCons' oPool' ns nc np fuel 0
          if c ≠ 0 then c
          else
            let c := nodeLoop w oNodes' oCons' oPool' ns nc nn np fuel 0
            if c ≠ 0 then c
            else ruleLoop w oSorts' oNodes' oCons' oRules' oSteps' oPool' nn nr nst np fuel fuel 0 0

end Lanius.Cert
