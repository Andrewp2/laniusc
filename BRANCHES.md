# Active branches (11-05)

`lang` (cc8cfec22) holds all merged work, and its gate passes. The rest are unmerged work,
newest first within each stream. `./track-branches.sh` (in this branch) makes a local branch
for each of them in one go.

| Branch | Agent | State | What it is |
|---|---|---|---|
| `regen-modules` | regen | WIP, unbuilt | Per-function compiler parts with stable names (about 3000 new part modules). Cuts the rebuild for adding a compiler function from 575 to 435 modules (simulated). Getting under 100 needs index-file proofs that take callee numbers as parameters (several days). Notes: regen/RESUME.md |
| `leafB` | leafB2 | merged into lang | F14 compile side: GenPC P02 failing lemmas 40 -> 2, LowerSlotsSmall stated. Notes: wt-leafB/RESUME.md |
| `leafB-lv` | leafB2 | ready, needs full build | compiler.lani: checks a view's length before lowering its body, and a string offset before adding to it (same programs accepted, proved in Mini/ChecksFirst.lean). Unblocks the last 2 P02 lemmas. |
| `leafC-s5b` | leafC | built except SelfBounded/SelfPre/LaniusOpen, gate not run | F5 S5b: `&self`/`&mut self` receivers as borrows, a ref parameter passed whole. Contains lang 07bb5c4a3. |
| `leafC-s6b` | leafC | compiler builds, rest unbuilt | F5 S6b: lowering of borrows, dereferences and places; borrowed locals get memory homes (Binding.home). On top of s5b. |
| `leafC-s6c` | leafC | compiler builds, rest unbuilt | F5 S6c: calls with references (borrow arguments, homed arrays lent with no copy). On top of s6b. TODO: `declare` must accept `.ref`; add an end-to-end `&mut` front-end case. |
| `leafA-p3b` | leafA | WIP, TypeSound does not build | F5 P3: proofs for S6b. Mini/LowerCases.lean (one lemma per lowering case) builds; trusted fix for eBorrow's Core meaning (17f203cc4); TypeSound eval side done. On top of leafC-s6b. Notes: leafA/RESUME.md ("PAUSED") and leafA/lowering-spec.md |
| `leafC-same` | leafC | unbuilt until p3b builds | The `same` lemmas' reference cases for S6c, on top of leafA-p3b. Notes: leafC/RESUME.md |
| `f6v-split` | f6v | WIP, build at 2125/2311 | F8 file model: World/Files types split from meanings, so a file-service body change rebuilds 210 jobs, not the library. Needs the rest of the build, the trusted hash (HASHTODO) and the gate. Then stage (c), the sandboxed file oracle. Notes: f6v/RESUME.md |
| `cert` | cert | merged into lang | Certificate checker spike (formal/cert, LaniusCert). Outcome is in cert/RESUME.md; reflection inside Lean was too slow. |
| `lv` | cert | merged into lang | The `lv` front-door tool (formal/tools/lv). |

Order once builds are cheap or a batch rebuild is allowed: leafB-lv, then leafC-s5b -> s6b -> s6c
together with leafA-p3b and leafC-same, then f6v-split. Overall state: reports/RESUME_STATE.md;
agent brief: reports/VC_RESTART_BRIEF.md.
