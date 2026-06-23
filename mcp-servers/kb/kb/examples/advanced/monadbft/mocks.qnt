
module mocks {
  import basicSpells.* from "./spells/basicSpells"
  import types.* from "types"

  // ProposalsMock

  // This is a mock environment extension to simulate proposal fetching
  type ProposalsMock = Set[Proposal]

  pure def fetch(s: ProposalsMock, p: ProposalID): Proposal = {
    s.find(pp => pp.proposal_id == p).unwrap()
  }

  pure def fetch_ancestors(m: AncestorsMock, id: ProposalID): Set[ProposalID] = {
    m.getOrElse(id, Set())
  }

  /// Check if a block was alread received
  pure def block_present(mock: ProposalsMock, bh: BlockHeader): bool = {
    mock.exists(p => p.block.header_from_block() == bh)
  }

  /// Fetch the block from the local state
  pure def get_present_block(mock: ProposalsMock, bh: BlockHeader): Block = {
    mock.find(p => p.block.header_from_block() == bh).unwrap().block
  }

  // AncesstorsMock

  // This is a mock environment extension to simulate ancestor fetching
  type AncestorsMock = ProposalID -> Set[ProposalID]

  pure def save_ancestor(m: AncestorsMock, id: ProposalID, parent: ProposalID): AncestorsMock = {
    m.setByWithDefault(id, s => s.setAdd(parent), Set())
  }
}
