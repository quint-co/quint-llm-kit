
/**
 * Information gathering to help understand how a decision was taken.
 *
 * This is not part of the core protocol, it's just instrumentation.
 *
 * Gabriela Moreira, Informal Systems, 2024
 */
module watcher {
  import basicSpells.* from "./spells/basicSpells"
  import mysticeti_types.* from "./mysticeti_types"

  val FAULTY = 1

  pure def link_edges(blocks: BlockStore, earlier_block: StatementBlock, later_block: StatementBlock): Set[Edge] = {
    val chains = range(earlier_block.reference.round + 1, later_block.reference.round + 1).foldl(Set([earlier_block]), (links, r) => {
      val r_blocks = blocks.by_round(r)
      links.map(l => {
        val linked_blocks = r_blocks.filter(block => block.parents.contains(l.last().reference))
        linked_blocks.map(b => l.append(b))
      }).flatten()
    }).filter(c => c.last() == later_block)

    chains.map(c => range(0, c.length() - 1).foldl(Set(), (edges, i) => {
      val parent = c[i]
      val child = c[i + 1]
      edges.union(Set((parent.reference.label, child.reference.label)))
    })).flatten()
  }

  pure def certified_link_edges(
    blocks: BlockStore,
    anchor_block: StatementBlock,
    proposer_block: StatementBlock
  ): Set[Edge] = {
    pure val potential_certified_links = blocks
      .children_of(proposer_block)
      .map(b => blocks.children_of(b))
      .flatten()

    potential_certified_links.filter(block => {
      blocks.is_certificate(block, proposer_block) and blocks.is_link(block, anchor_block)
    }).map(b => {
      blocks.edges_from_certificate(b, proposer_block)
        .union(blocks.link_edges(b, anchor_block))
    }).flatten()
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

  pure def edges_from_certificate(blocks: BlockStore,
    certificate_block: StatementBlock,
    proposer_block: StatementBlock
  ): Set[Edge] = {
    pure val parents_supporting_proposer = certificate_block.parents.filter(b => {
      blocks.by_reference(b).parents.contains(proposer_block.reference)
    })
    if (parents_supporting_proposer.size() >= 2*FAULTY + 1) {
      pure val edges_to_add = parents_supporting_proposer.map(parent => {
        Set(
          (parent.label, certificate_block.reference.label),
          (proposer_block.reference.label, parent.label),
        )
      }).flatten()
      edges_to_add
    } else {
      Set()
    }
  }

  pure def log_direct_decision(blocks: BlockStore, proposer_block: StatementBlock, certificates: Set[StatementBlock]): Log = {
    pure val supporting_edges: Set[Edge]= certificates.map(certificate_block => {
      blocks.edges_from_certificate(certificate_block, proposer_block)
    }).flatten()
    DirectDecision({
      certificate_blocks: certificates.map(b => b.reference.label),
      supporting_edges: supporting_edges
    })
  }

  pure def log_indirect_decision(blocks: BlockStore, proposer_block: StatementBlock, anchor: StatementBlock): Log = {
    IndirectDecision({
      anchor: anchor.reference.label,
      edges: blocks.certified_link_edges(anchor, proposer_block)
    })
  }
}
