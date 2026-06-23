
/**
 * Types and basic functionality for the Mysticeti consensus algorithm in `mysticeti_c.qnt`
 *
 * Gabriela Moreira, Informal Systems, 2024
 */
module mysticeti_types {
  import basicSpells.* from "./spells/basicSpells"

  type ProposerSlotState = Commit | Skip | Undecided
  type Decision = { status: ProposerSlotState, block: BlockReference, log: Log }
  type Edge = (str, str)
  type Log = IncompleteWave | DirectDecision({ certificate_blocks: Set[str], supporting_edges: Set[Edge] }) | IndirectDecision({ anchor: str, edges: Set[Edge] }) | Error | UnableToDecide

  type BlockReference = { authority: int, round: int, label: str, leader_rank: int }
  type StatementBlock = { reference: BlockReference, parents: Set[BlockReference] }

  // Map from round to validator to block
  type BlockStore = int -> int -> StatementBlock

  /* Basic DAG functionality */

  pure def children_of(blocks: BlockStore, block: StatementBlock): Set[StatementBlock] = {
    pure val potential_children = blocks.by_round(block.reference.round + 1)
    potential_children.filter(child => child.parents.contains(block.reference))
  }

  pure def is_link(blocks: BlockStore, earlier_block: StatementBlock, later_block: StatementBlock): bool = {
    val linked_to_earlier = range(earlier_block.reference.round + 1, later_block.reference.round + 1)
      .foldl(Set(earlier_block), (linked_blocks, r) => {
        val r_blocks = blocks.by_round(r)
        linked_blocks.union(r_blocks.filter(block => linked_blocks.exists(b => block.parents.contains(b.reference))))
      })

    linked_to_earlier.contains(later_block)
  }

  pure def by_reference(blocks: BlockStore, reference: BlockReference): StatementBlock = {
    blocks.get(reference.round).get(reference.authority)
  }

  pure def by_round(blocks: BlockStore, round: int): Set[StatementBlock] = {
    blocks.getOrElse(round, Map()).values()
  }

  pure def edge(b1: StatementBlock, b2: StatementBlock): Edge = {
    (b1.reference.label, b2.reference.label)
  }

  pure def highest_round(blocks: BlockStore): int = {
    blocks.keys().fold(0, max)
  }
  
  // TODO: Equivocation: we can have multiple blocks from same round/author
  pure def to_block_store(dag) = {
    dag.fold(Map(), (m, block) => {
      if (m.has(block.reference.round)) {
        m.setBy(block.reference.round, row => row.put(block.reference.authority, block))
      } else {
        m.put(block.reference.round, Map(block.reference.authority -> block))
      }
    })
  }
}
