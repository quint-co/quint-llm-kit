
/**
 * A test describing the scenario presented in Appendix A on the Mysticeti paper [1] 
 *
 * [1]: https://arxiv.org/pdf/2310.14821
 *
 * Gabriela Moreira, Informal Systems, 2024
 */
module mysticeti_paper_test {
  import basicSpells.* from "./spells/basicSpells"
  import mysticeti_c.* from "./mysticeti_c"
  import mysticeti_types.* from "./mysticeti_types"

  // The paper labels nodes as L<round><rank> where ranks are "a" < "b" < "c" < "d"
  pure val L1a = { authority: 0, round: 0, label: "L1a", leader_rank: 0 }
  pure val L1b = { authority: 1, round: 0, label: "L1b", leader_rank: 1 }
  pure val L1c = { authority: 2, round: 0, label: "L1c", leader_rank: 2 }
  pure val L1d = { authority: 3, round: 0, label: "L1d", leader_rank: 3 }
  pure val L2d = { authority: 0, round: 1, label: "L2d", leader_rank: 3 }
  pure val L2a = { authority: 1, round: 1, label: "L2a", leader_rank: 0 }
  pure val L2b = { authority: 2, round: 1, label: "L2b", leader_rank: 1 }
  pure val L2c = { authority: 3, round: 1, label: "L2c", leader_rank: 2 }
  pure val L3c = { authority: 0, round: 2, label: "L3c", leader_rank: 2 }
  pure val L3d = { authority: 1, round: 2, label: "L3d", leader_rank: 3 }
  pure val L3b = { authority: 3, round: 2, label: "L3b", leader_rank: 1 }
  pure val L4d = { authority: 0, round: 3, label: "L4d", leader_rank: 3 }
  pure val L4a = { authority: 1, round: 3, label: "L4a", leader_rank: 0 }
  pure val L4b = { authority: 2, round: 3, label: "L4b", leader_rank: 1 }
  pure val L4c = { authority: 3, round: 3, label: "L4c", leader_rank: 2 }
  pure val L5c = { authority: 0, round: 4, label: "L5c", leader_rank: 2 }
  pure val L5d = { authority: 1, round: 4, label: "L5d", leader_rank: 3 }
  pure val L5a = { authority: 2, round: 4, label: "L5a", leader_rank: 0 }
  pure val L5b = { authority: 3, round: 4, label: "L5b", leader_rank: 1 }
  pure val L6b = { authority: 0, round: 5, label: "L6b", leader_rank: 1 }
  pure val L6c = { authority: 1, round: 5, label: "L6c", leader_rank: 2 }
  pure val L6d = { authority: 2, round: 5, label: "L6d", leader_rank: 3 }

  pure val DAG = Set(
    { reference: L1a, parents: Set() },
    { reference: L1b, parents: Set() },
    { reference: L1c, parents: Set() },
    { reference: L1d, parents: Set() },
    { reference: L2d, parents: Set(L1a, L1b, L1c) },
    { reference: L2a, parents: Set(L1a, L1b, L1d) },
    { reference: L2b, parents: Set(L1a, L1c, L1d) },
    { reference: L2c, parents: Set(L1a, L1c, L1d) },
    { reference: L3c, parents: Set(L2d, L2a, L2b) },
    { reference: L3d, parents: Set(L2d, L2a, L2c) },
    { reference: L3b, parents: Set(L2d, L2a, L2b, L2c) },
    { reference: L4d, parents: Set(L3c, L3d, L3b) },
    { reference: L4a, parents: Set(L3c, L3d, L3b) },
    { reference: L4b, parents: Set(L3c, L3d, L3b) },
    { reference: L4c, parents: Set(L3c, L3d, L3b) },
    { reference: L5c, parents: Set(L4d, L4b, L4c) },
    { reference: L5d, parents: Set(L4d, L4a, L4b, L4c) },
    { reference: L5a, parents: Set(L4d, L4b, L4c) },
    { reference: L5b, parents: Set(L4d, L4b, L4c) },
    { reference: L6b, parents: Set(L5c, L5d, L5a, L5b) },
    { reference: L6c, parents: Set(L5d, L5a, L5b) },
    { reference: L6d, parents: Set(L5d, L5a, L5b) }
  )

  pure def is_direct(l: Log): bool = {
    match l {
      | DirectDecision(_) => true
      | _ => false
    }
  }

  pure def is_indirect(l: Log): bool = {
    match l {
      | IndirectDecision(_) => true
      | _ => false
    }
  }

  pure def anchor(l: Log): Option[str] = {
    match l {
      | IndirectDecision(r) => Some(r.anchor)
      | _ => None
    }
  }


  var blocks: BlockStore
  var decisions: List[Decision]
  var blocks_to_commit: List[BlockReference]

  action init = all {
    blocks' = Map(),
    decisions' = [],
    blocks_to_commit' = [],
  }

  action step = {
    val new_decisions = try_decide_all(blocks)
    all {
      blocks' = blocks,
      decisions' = new_decisions,
      blocks_to_commit' = commit_order(new_decisions),
    }
  }

  action init_with_dag = all {
    blocks' = DAG.to_block_store(),
    decisions' = [],
    blocks_to_commit' = [],
  }

  run paperTest = init_with_dag.then(step).then(
    val decision_by_block = decisions.foldl(Map(), (m, decision) => {
      m.put(decision.block.label, decision)
    })
    all {
      // The resulting commit sequence is L1a, L1c, L1d, L2a
      assert(blocks_to_commit.listMap(b => b.label) == ["L1a", "L1c", "L1d", "L2a"]),

      // Rounds 5 and 6 are part of an incomplete wave and therefore undecided
      assert(decision_by_block.get("L6d").status == Undecided),
      assert(decision_by_block.get("L6d").log == IncompleteWave),
      // ...
      assert(decision_by_block.get("L5a").status == Undecided),
      assert(decision_by_block.get("L5a").log == IncompleteWave),

      // L4d, L4c and L4b are marked as commit by the direct decision rule
      assert(decision_by_block.get("L4d").status == Commit),
      assert(decision_by_block.get("L4d").log.is_direct()),
      assert(decision_by_block.get("L4c").status == Commit),
      assert(decision_by_block.get("L4c").log.is_direct()),
      assert(decision_by_block.get("L4b").status == Commit),
      assert(decision_by_block.get("L4b").log.is_direct()),

      // L4a is marked as skip by the direct decision rule
      assert(decision_by_block.get("L4a").status == Skip),
      assert(decision_by_block.get("L4a").log.is_direct()),

      // Continuing with L3d, L3c, L3b, and L2d, the direct decision rule
      // categorizes them all as to-commit, similar to L4d, L4c, L4b
      assert(decision_by_block.get("L3d").status == Commit),
      assert(decision_by_block.get("L3d").log.is_direct()),
      assert(decision_by_block.get("L3c").status == Commit),
      assert(decision_by_block.get("L3c").log.is_direct()),
      assert(decision_by_block.get("L3b").status == Commit),
      assert(decision_by_block.get("L3b").log.is_direct()),
      assert(decision_by_block.get("L2d").status == Commit),
      assert(decision_by_block.get("L2d").log.is_direct()),

      // L2c and L2b cannot be classified with direct decision, so indirect
      // decision rule is used. The anchor is L5a, which is undecided.
      // Therefore, the status is undecided.
      assert(decision_by_block.get("L2c").status == Undecided),
      assert(decision_by_block.get("L2c").log.is_indirect()),
      assert(decision_by_block.get("L2c").log.anchor() == Some("L5a")),
      assert(decision_by_block.get("L2b").status == Undecided),
      assert(decision_by_block.get("L2b").log.is_indirect()),
      assert(decision_by_block.get("L2b").log.anchor() == Some("L5a")),

      // L2a is a direct decision on commit
      assert(decision_by_block.get("L2a").status == Commit),
      assert(decision_by_block.get("L2a").log.is_direct()),

      // L1d and L1c need indirect decision, and the anchor is L4b, which is
      // marked as Commit
      assert(decision_by_block.get("L1d").status == Commit),
      assert(decision_by_block.get("L1d").log.is_indirect()),
      assert(decision_by_block.get("L1d").log.anchor() == Some("L4b")),
      assert(decision_by_block.get("L1c").status == Commit),
      assert(decision_by_block.get("L1c").log.is_indirect()),
      assert(decision_by_block.get("L1c").log.anchor() == Some("L4b")),

      // NOTE: description on paper seems wrong here (Appendix A) as it says
      // anchor is L4a, while the referred figure shows L4b as the anchor.
      // L1b also needs indirect decision with anchor L4b, but
      // there is no certified link between it and the anchor, so it gets marked
      // as Skip
      assert(decision_by_block.get("L1b").status == Skip),
      assert(decision_by_block.get("L1b").log.is_indirect()),
      assert(decision_by_block.get("L1b").log.anchor() == Some("L4b")),

      // L1a is a direct decision on commit
      assert(decision_by_block.get("L1a").status == Commit),
      assert(decision_by_block.get("L1a").log.is_direct()),

      blocks' = blocks,
      decisions' = decisions,
      blocks_to_commit' = blocks_to_commit,
    })

    // Lemma 7. All correct validators commit a consistent sequence of proposer
    // blocks (i.e., the committed proposer sequence of one correct validator is
    // a prefix of another’s).
    // We also check this lemma with an invariant. This is a weaker test over a much less general scenario.
    run lemma7Test = {
      nondet a1 = 0.to(NUM_OF_PROPOSERS - 1).oneOf()
      nondet a2 = 0.to(NUM_OF_PROPOSERS - 1).exclude(Set(a1)).oneOf()
      nondet r1 = 0.to(NUM_OF_PROPOSERS - 1).oneOf()
      nondet r2 = 0.to(NUM_OF_PROPOSERS - 1).exclude(Set(r1)).oneOf()
      nondet parents1 = blocks.get(5).values().map(b => b.reference).powerset().oneOf()
      nondet parents2 = blocks.get(5).values().map(b => b.reference).powerset().oneOf()
      val block1: StatementBlock = { reference: { round: 6, authority: a1, label: "new1", leader_rank: r1 }, parents: parents1 }
      val block2: StatementBlock = { reference: { round: 6, authority: a2, label: "new2", leader_rank: r2 }, parents: parents2 }

      init_with_dag.then(all {
        val b1 = blocks.put(6, Map(a1 -> block1))
        val d1 = commit_order(try_decide_all(b1))

        val b2 = blocks.put(6, Map(a2 -> block2))
        val d2 = commit_order(try_decide_all(b2))

        val b3 = blocks.put(6, Map(a1 -> block1, a2 -> block2))
        val d3 = commit_order(try_decide_all(b3))
        all {
          assert(d1.isPrefixOf(d3)),
          assert(d2.isPrefixOf(d3)),
        },
        blocks' = blocks,
        decisions' = decisions,
        blocks_to_commit' = blocks_to_commit,
    })
  }
}
