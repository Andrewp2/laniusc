// src/lexer/tables/build.rs
use std::time::Instant;

use hashbrown::{HashMap, HashSet};
use rayon::prelude::*;

use super::{
    Tables,
    dfa::{N_STATES, Next, StreamingDfa},
};

// Q -> (Q, emit)
#[derive(Clone)]
struct UFunc {
    trans: Vec<Next>, // len = #states
}

#[inline]
fn compose_trans(a: &[Next], b: &[Next]) -> Vec<Next> {
    let n = a.len();
    let mut out = Vec::with_capacity(n);
    for s in 0..n {
        let Next { state: mid, .. } = a[s];
        let Next { state, emit } = b[mid as usize];
        out.push(Next { state, emit }); // keep LAST edge emit flag
    }
    out
}

fn closure_fixpoint_parallel(funcs: &mut Vec<UFunc>, map: &mut HashMap<Vec<Next>, u32>) {
    let mut round = 0usize;
    let mut new_start = 0usize; // treat current set as "new" in first round

    loop {
        let cur_len = funcs.len();
        let new_idxs: Vec<usize> = (new_start..cur_len).collect();
        if new_idxs.is_empty() {
            break;
        }
        let all_idxs: Vec<usize> = (0..cur_len).collect();

        // new × all
        let set1: HashSet<Vec<Next>> = new_idxs
            .par_iter()
            .fold(HashSet::new, |mut local, &i| {
                let ai = &funcs[i].trans;
                for &j in &all_idxs {
                    let bj = &funcs[j].trans;
                    let trans = compose_trans(ai, bj);
                    if !map.contains_key(&trans) {
                        local.insert(trans);
                    }
                }
                local
            })
            .reduce(HashSet::new, |mut a, b| {
                a.extend(b);
                a
            });

        // all × new
        let set2: HashSet<Vec<Next>> = all_idxs
            .par_iter()
            .fold(HashSet::new, |mut local, &i| {
                let ai = &funcs[i].trans;
                for &j in &new_idxs {
                    let bj = &funcs[j].trans;
                    let trans = compose_trans(ai, bj);
                    if !map.contains_key(&trans) {
                        local.insert(trans);
                    }
                }
                local
            })
            .reduce(HashSet::new, |mut a, b| {
                a.extend(b);
                a
            });

        // Insert sequentially to assign stable IDs
        let mut added = 0usize;
        for trans in set1.into_iter().chain(set2.into_iter()) {
            if !map.contains_key(&trans) {
                let id = funcs.len() as u32;
                map.insert(trans.clone(), id);
                funcs.push(UFunc { trans });
                added += 1;
            }
        }

        round += 1;
        println!("[tables] closure round {round}: size now {}", funcs.len());

        if added == 0 {
            break;
        }
        new_start = cur_len;
    }
}

fn build_merge_and_maps_parallel(
    funcs: &Vec<UFunc>,
    map: &HashMap<Vec<Next>, u32>,
    start_state_idx: usize,
    token_map: &[u32; N_STATES],
) -> (Vec<u32>, Vec<u32>) {
    let m = funcs.len();
    let mut merge = vec![0u32; m * m];

    // Fill rows in parallel.
    let m_us = m;
    merge.par_chunks_mut(m_us).enumerate().for_each(|(a, row)| {
        let at = &funcs[a].trans;
        for b in 0..m_us {
            let bt = &funcs[b].trans;
            let trans = compose_trans(at, bt);
            let id = *map
                .get(&trans)
                .expect("closure should intern all compositions");
            row[b] = id;
        }
    });

    let mut token_of = vec![super::tokens::INVALID_TOKEN; m];
    for (id, f) in funcs.iter().enumerate() {
        let Next { state, .. } = f.trans[start_state_idx];
        token_of[id] = token_map[state as usize];
    }

    (merge, token_of)
}
