
module types {
  import basicSpells.* from "./spells/basicSpells"
  import choreo from "./choreo"
  //
  // Data structures (page 8)
  //

  type Ledger = List[Proposal]
  type ProposalID = { seq: int, view: int, byzantine: int }
  // The signature is symbolic, we represent it with the sender address
  type Signature = Address
  // We don't model hashes explicitly, but under the assumption of collision-free hash functions,
  // we can use this model to test for equality.
  type StateHash = List[ProposalID]

  /// ⟨view, proposal id, block header, σ, nec⟩ (page 8)
  type Tip = {
    view: int,
    proposal_id: ProposalID,
    block_header: BlockHeader,
    sigma: Signature,
    nec: Option[NEC],
  }

  /// ⟨view, seq, proposal id, state hash, σ⟩ (page 8)
  type VoteMsg = {
    view: int,
    seq: int,
    proposal_id: ProposalID,
    state_hash: StateHash,
    sigma: Signature,
  }

  /// ⟨view, highqc_view, σ⟩ (page 9)
  type NoEndorsementMsg = {
    view: int,
    highqc_view: int,
    sigma: Signature,
  }

  /// ⟨view, tip, tc, σ⟩ (page 9)
  type TimeoutMsg = {
    view: int,
    tip: Tip,
    // Timeout certificate use tc.view. Needed to avoid cyclic data type.
    // TODO: Maybe this should be an option
    tc: TCAux,
    sigma: Signature,
  }

  /// ⟨view, seq, proposal id, state hash, Σ⟩ (page 8)
  type QC = {
    c: Set[VoteMsg],
    view: int,
    seq: int,
    proposal_id: ProposalID,
    state_hash: StateHash,
    sigma: Signature,
  }

  /// TC = ⟨view, tips, high_tip, Σ⟩ (page 9)
  type TC = {
    view: int,
    high_tip: Option[Tip],
    tips: Set[Tip],
    sigma: Signature,
    c: Set[TimeoutMsg],
  }

  /// Auxiliary type for timeout certificate to avoid circular data types
  type TCAux = {
    view: int,
    high_tip: Option[Tip],
    tips: Set[Tip],
    sigma: Signature,
  }

  /// ⟨view, highqc view, Σ⟩ (page 9)
  type NEC = {
    view: int,
    highqc_view: int,
    sigma: Signature,
    c: Set[NoEndorsementMsg]
  }

  /// We don't model hashes explicitly, but under the assumption of collision-free hash functions,
  /// we can use this model to test for equality.
  type BlockHash = {
    seq: int,
    payload_hash: str,
    qc: QC
  }

  /// ⟨seq, payload, payload hash, qc, block hash⟩ (page 8)
  type Block = {
    seq: int,
    payload: str,
    payload_hash: str,
    qc: QC,
    block_hash: BlockHash
  }

  /// ⟨seq, payload hash, qc, block hash⟩ (page 8)
  type BlockHeader = {
    seq: int,
    payload_hash: str,
    qc: QC,
    block_hash: BlockHash
  }

  /// ⟨view, proposal id, block, σ, tc, nec⟩ (page 8)
  type Proposal = {
    view: int,
    proposal_id: ProposalID,
    block: Block,
    sigma: Signature,
    tc: Option[TC],
    nec: Option[NEC],
  }

  type Address = str

  type TimeoutData = int
  type InternalEvent =
    | TimeoutEvent(TimeoutData)

  type Message =
    | Prop(Proposal)
    | Vote(VoteMsg)
    | Timeout(TimeoutMsg)
    // | NoEndorsement(NoEndorsementMsg)

  type CustomEffects =
    | LogMessage(Message)
    | LogProposal(Proposal)
    | LogCommit((Address, Proposal))
    | EarlyConfirmation(Proposal)
    | Confirmation(Proposal)
    // Algorithm 5 (block recovery) has more responses

  type Logging = {
    committed_proposals: Address -> Set[Proposal],
    msgHistory: Set[Message],
    timeoutHistory: Set[TimeoutData],
  }

  type EnvExtensions = {
    proposals_mock: Set[Proposal],
    ancestors_mock: ProposalID -> Set[ProposalID],
    logging: Logging,
  }

  type State = {
    // Variables from Algorithm 2
    high_tip: Option[Tip],
    tip: Option[Tip],
    last_tc: Option[TC],
    curView: int,
    ledger: Ledger,
    highest_voted_view: int,
    // Set of view numbers for which a timeout was broadcast (Alg 4 line 21/22)
    timeouts_already_broadcast: Set[int],
  }

  /* Boilerplate */
  type LocalState = choreo::LocalState[Address, State]
  type LocalContext = choreo::LocalContext[Address, State, Message, InternalEvent, EnvExtensions]
  type Transition = choreo::Transition[Address, State, Message, InternalEvent, CustomEffects]
  type GlobalContext = choreo::GlobalContext[
    Address,
    State,
    Message,
    InternalEvent,
    EnvExtensions
  ]
  /* End of boilerplate */


  // Basic type conversions

  /// Extract the block header out of a block
  pure def header_from_block(b: Block): BlockHeader = {
    {
      seq: b.seq,
      payload_hash: b.payload_hash,
      qc: b.qc,
      block_hash: b.block_hash,
    }
  }
}
