
/**
 * Functional Mysticeti consensus algorithm [1].
 * Comments between quotes contain text from the paper.
 *
 * [1]: https://arxiv.org/pdf/2310.14821
 *
 * Gabriela Moreira, Informal Systems, 2024-2025
 */
module mysticeti_c {
  import basicSpells.* from "./spells/basicSpells"
  import rareSpells.* from "./spells/rareSpells"

  import mysticeti_types.* from "./mysticeti_types"
  import watcher from "./watcher"

  pure val NUM_OF_PROPOSERS = 4
  pure val FAULTY = 1

  // This spec assumes wave lenght of three. Since there Quint doesn't allow
  // recursion, it would not be trivial to generalize it for any wave length.

  /// "The direct decision rule marks a slot as to-skip if it observes a skip pattern for that slot.
  /// That is for any proposal for the slot (there may be multiple due to potential equivocation)
  /// it observes 2f + 1 blocks that do not support it or support no proposal." 
  pure def should_skip(blocks: BlockStore, proposal: StatementBlock): bool = {
    pure val next_round_blocks = blocks.by_round(proposal.reference.round + 1)
    pure val non_supporters = next_round_blocks.filter(block => {
      not(block.parents.exists(parent => parent == proposal.reference))
    })

    non_supporters.size() >= 2 * FAULTY + 1
  }

  /// The anchor has a certified link with a proposer block iff it
  /// "causally references a certificate pattern over the [block's] slot"
  pure def has_certified_link(
    blocks: BlockStore,
    anchor_block: StatementBlock,
    proposer_block: StatementBlock
  ): bool = {
    pure val potential_certified_links = blocks
      .children_of(proposer_block)
      .map(b => blocks.children_of(b))
      .flatten()

    potential_certified_links.exists(block => {
      blocks.is_certificate(block, proposer_block) and blocks.is_link(block, anchor_block)
    })
  }

  /// A certificate should have at least 2F + 1 parents that support (link to) the proposer block.
  pure def is_certificate(
    blocks: BlockStore,
    certificate_block: StatementBlock,
    proposer_block: StatementBlock
  ): bool = {
    pure val parents_supporting_proposer = certificate_block.parents.filter(b => {
      blocks.by_reference(b).parents.contains(proposer_block.reference)
    })

    parents_supporting_proposer.size() >= 2*FAULTY + 1
  }

  // The certificate pattern, illustrated by Figure 3 (right), where at least 2f + 1 blocks
  // at round r + 1 support a block B ≡ (A, r, h). We then say that B is certified.
  // Any subsequent block (illustrated at r+2) that constrains in its history such a pattern
  // is called a certificate for the block B.
  pure def find_certificates(blocks: BlockStore, proposer_block: StatementBlock): Set[StatementBlock] = {
    // A certificate for a block in round r will be in r + 2,
    // so we fetch the children of the children of the proposer_block
    pure val potential_certificates = blocks
      .children_of(proposer_block)
      .map(b => blocks.children_of(b))
      .flatten()
  
    potential_certificates.filter(c => blocks.is_certificate(c, proposer_block))
  }

  pure def try_direct_decide(blocks: BlockStore, proposer_block: StatementBlock): Decision = {
    // "The validator marks a slot as to-commit if it observes 2f + 1 commit patterns for that slot,
    // that is, if it accumulates 2f + 1 distinct implicit certificate blocks for it"
    pure val certificates = blocks.find_certificates(proposer_block)
    
    pure val status = if (should_skip(blocks, proposer_block)) {
      Skip
    } else if (certificates.size() >= 2*FAULTY + 1) {
      Commit
    } else {
      // "If the direct decision rule fails to mark a slot as either
      // to-commit or to-skip, the slot remains undecided and the
      // validator resorts to the indirect decision rule"
      Undecided
    }

    {
      status: status,
      block: proposer_block.reference,
      log: watcher::log_direct_decision(blocks, proposer_block, certificates)
    }
  }

  /// "If the direct decision rulefails to determine the slot, the validator resorts
  /// to the indirect decision rule to attempt to reach a decision for the slot"
  pure def try_indirect_decide(
    blocks: BlockStore,
    sequence: List[Decision],
    proposer_block: StatementBlock
  ): Decision = {
    // "This rule operates in two stages. It initially searches for an anchor,
    // which is defined as the first slot with the round number (r′ > r + 2)
    // that is already marked as either undecided or to-commit"

    // The anchor will always be in the first round of the next wave or later
    pure val anchor_round = proposer_block.reference.round + 3
    pure val potential_anchors = sequence
      .select(s => s.block.round >= anchor_round)
      // Anchors are sorted by their round and leadership rank
      .sortList((a, b) => {
        if (a.block.round != b.block.round) {
          a.block.round < b.block.round
        } else {
          a.block.leader_rank < b.block.leader_rank
        }
      })

    pure val chosen_anchor = potential_anchors.findFirst(decision => {
      decision.status == Undecided or decision.status == Commit
    })

    match chosen_anchor {
      | None => { status: Undecided, block: proposer_block.reference, log: UnableToDecide }
      | Some(anchor) => {
        if (anchor.status == Undecided) {
          // "If the anchor is marked as undecided the validator marks the slot as undecided (Figure 4d)."
          {
            status: Undecided,
            block: proposer_block.reference,
            log: IndirectDecision({ anchor: anchor.block.label, edges: Set() }),
          }
        } else {
          // "Conversely, if the anchor is marked as to-commit, the validator marks the slot either
          // as to-commit if the anchor causally references a certificate pattern over the slot or
          // as to-skip in the absence of a certificate pattern"
          pure val b_anchor = blocks.by_reference(anchor.block)
          pure val status = if (blocks.has_certified_link(b_anchor, proposer_block)) {
            Commit
          } else {
            Skip
          }

          {
            status: status,
            block: proposer_block.reference,
            log: watcher::log_indirect_decision(blocks, proposer_block, b_anchor),
          }
        }
      }
    }
  }

  pure def try_decide_one(
    blocks: BlockStore,
    sequence: List[Decision],
    round: int,
    authority: int
  ): List[Decision] = {
    pure val proposer_block = blocks.get(round).get(authority)

    if (round > blocks.highest_round() - 2) {
      // The wave is incomplete, we can not decide
      (
        [{ status: Undecided, block: proposer_block.reference, log: IncompleteWave }]
          .concat(sequence)
      )
    } else {
      pure val direct_decision = try_direct_decide(blocks, proposer_block)
      pure val decision = if (direct_decision.status != Undecided) {
        direct_decision
      } else {
        try_indirect_decide(blocks, sequence, proposer_block)
      }

      // Add the new decision to the head of the decision sequence
      ([decision].concat(sequence))
    }
  }

  /// Iterate from the highest round to the lowest, and from the last leader (proposer)
  /// to the first, collecting potential decisions on whether thay should commit or
  /// skip blocks at that (round, leader).
  pure def try_decide_all(blocks: BlockStore): List[Decision] = {
    // FIXME: we don't have to run all the way to round 0 if there are commited rounds
    decreasingRange(blocks.highest_round(), 0).foldl([], (sequence, round) => {
      decreasingRange(NUM_OF_PROPOSERS - 1, 0).foldl(sequence, (sequence, proposer) => {
        // There can be more than one block for (round, proposer)

        // We know the proposer index, but `proposer` refers to the leader rank.
        // Find the authority for this rank.
        pure val authority = blocks
          .getOrElse(round, Map())
          .values()
          .find(b => b.reference.leader_rank == proposer)

        match authority {
           | None => sequence
           | Some(block) => {
              try_decide_one(blocks, sequence, block.reference.round, block.reference.authority)
           }
         }
      })
    })
  }

  // "After processing all slots, the validator derives an ordered sequence of slots. Subsequently,
  // the validator iterates over that sequence, committing all slots marked as to-commit and
  // skipping all slots marked as to-skip.
  // This iteration continues until the first undecided slot is encountered."
  pure def commit_order(decisions: List[Decision]): List[BlockReference] = {
    decisions
      .takeWhile(decision => decision.status != Undecided)
      .select(decision => decision.status == Commit)
      .listMap(decision => decision.block)
  }
}
