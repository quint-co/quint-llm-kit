
module instance {
  import basicSpells.* from "./spells/basicSpells"
  import types.* from "types"

  import monadbft(validators = Set("v1", "v2", "v3", "v4"), F = 1).* from "monadbft"
  // import monadbft(validators = Set("v1", "v2", "v3", "v4"), F = 1).* from "monadbftMicro"

  pure val sigs = range(0, 5).foldl(List(), (acc,v) => acc.append(leader_from_view(v)))
  pure val genesis_qc = {
    c: Set(),
    view: 0,
    seq: 0,
    proposal_id: { seq: 0, view: 0, byzantine: 0 },
    state_hash: List(),
    sigma: sigs[0],
  }

  pure val b1 = build_block(genesis_qc, "VALID_TRANSACTION_INIT_1")
  pure val p1 = build_proposal(1, b1, None, None, sigs[1])
  pure val votes1 = validators.map(v => {
    { view: 1, seq: 1, proposal_id: p1.proposal_id, state_hash: List(), sigma: v }
  })
  pure val qc1 = build_qc(votes1, sigs[2], List()).unwrap()
  pure val b2 = build_block(qc1, "VALID_TRANSACTION_INIT_2")
  pure val p2 = build_proposal(2, b2, None, None, sigs[2])
  pure val votes2 = validators.map(v => {
    { view: 2, seq: 2, proposal_id: p2.proposal_id, state_hash: List(p1.proposal_id), sigma: v }
  })
  pure val qc2 = build_qc(votes2, sigs[3], List(p1.proposal_id)).unwrap()
  pure val b3 = build_block(qc2, "VALID_TRANSACTION_INIT_3")
  pure val p3 = build_proposal(3, b3, None, None, sigs[3])
  pure val votes3 = validators.map(v => {
    { view: 3, seq: 3, proposal_id: p3.proposal_id, state_hash: List(p1.proposal_id, p2.proposal_id), sigma: v }
  })
  pure val qc3 = build_qc(votes3, sigs[4], List(p1.proposal_id, p2.proposal_id)).unwrap()
  pure val b4 = build_block(qc3, "VALID_TRANSACTION_INIT_4")
  pure val p4 = build_proposal(4, b4, None, None, sigs[4])

  pure val ancestors_4 = Map(
    p1.proposal_id -> Set(p1.proposal_id),
    p2.proposal_id -> Set(p1.proposal_id),
    p3.proposal_id -> Set(p1.proposal_id, p2.proposal_id),
    p4.proposal_id -> Set(p1.proposal_id, p2.proposal_id, p3.proposal_id)
  )
  pure val proposals_4 = Set(p1, p2, p3, p4)

  pure val initial_messages = Set(Prop(p4))

  pure def initialize_process(process_id: Address): LocalState = {
    val base = initialize_process_empty(process_id)
    {
      ...base,
      curView: 2,
      ledger: List(p1, p2),
      highest_voted_view: 3,
      tip: Some({
        view: 3,
        proposal_id: p3.proposal_id,
        block_header: header_from_block(b3),
        sigma: p3.sigma,
        nec: None,
      })
    }
  }

  pure val initial_logging: Logging = {
    committed_proposals: validators.mapBy(_ => Set(p1, p2)),
    msgHistory: votes1.union(votes2).map(x => Vote(x)),
    timeoutHistory: Set(),
  }

  pure val initial_extensions = {
    logging: initial_logging,
    proposals_mock: proposals_4,
    ancestors_mock: ancestors_4,
  }

  action init = init_from(initialize_process, initial_messages, initial_extensions)
}
