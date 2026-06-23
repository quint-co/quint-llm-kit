
module monadbft {
  import basicSpells.* from "./spells/basicSpells"
  import rareSpells.* from "./spells/rareSpells"
  import choreo(processes = validators) as choreo from "./choreo"
  import types.* from "types"
  import utils.* from "utils"
  import mocks.* from "mocks"

  /// Set of validators participating in the consensus.
  const validators: Set[Address]
  /// Number of byzantine nodes
  const F: int

  /// Number of votes needed to reach consensus
  pure val Q = 2 * F + 1
  /// Number of nodes
  pure val N = validators.size()
  pure val leaders = validators.fold(List(), (acc, v) => acc.append(v))

  pure val BLOCK_PAYLOAD = "VALID_TRANSACTION"

  type Input = choreo::Input[Message, InternalEvent]

  //
  // Utility functions
  //

  pure def mark_already_broadcast_timeout(s: LocalState, view: int): LocalState = {
    { ...s, timeouts_already_broadcast: s.timeouts_already_broadcast.setAdd(view) }
  }

  pure def add_timeouts(s: LocalState, view: int, timeouts: Set[TimeoutMsg]): LocalState = {
    { ...s, timeouts: s.timeouts.put(view, timeouts) }
  }

  pure def add_votes(s: LocalState, proposal_id: ProposalID, votes: Set[VoteMsg]): LocalState = {
    { ...s, votes: s.votes.put(proposal_id, votes) }
  }

  /// Hash is modeled as identity for payloads
  pure def hash(s: str): str = {
    s
  }

  /// Block hash is modeled as a tuple of the block seq, the payload hash and the qc
  pure def hash_block(seq: int, payload_hash: str, qc: QC): BlockHash = {
    { seq: seq, payload_hash: payload_hash, qc: qc }
  }

  /// Cryptographic hash to the post‐execution state
  /// Modeled here as the ordered list of executed proposal ids
  pure def state_hash(s: LocalState): StateHash = {
    s.ledger.foldl(List(), (acc, p) => acc.append(p.proposal_id))
  }

  pure def leader_from_view(view: int): Address = {
    leaders[view % leaders.length()]
  }

  /// Check if a node(other) is the leader of some view
  pure def is_leader(s: LocalState, signature: Address): bool =
    leader_from_view(s.curView) == signature

  /// Check if the node(self) is the leader of the current view
  pure def am_i_leader(s: LocalState): bool =
    leader_from_view(s.curView) == s.process_id

  /// Check if qc1 extends qc2
  pure def extend(qc1: QC, qc2: QC, ancestors_mock: AncestorsMock): bool =
    ancestors_mock.fetch_ancestors(qc1.proposal_id).contains(qc2.proposal_id)

  /// Check if two proposals are conflicting
  pure def conflicting_props(p1: Proposal, p2: Proposal, ancestors: ProposalID -> Set[ProposalID]): bool =
    and {
      not(extend(p1.block.qc, p2.block.qc, ancestors)),
      not(extend(p2.block.qc, p1.block.qc, ancestors)),
    }

  /// Extract the tips from a set of timeout messages
  /// This function retruns a set of Tips.
  pure def get_tips_from_timeouts(msgs: Set[TimeoutMsg]): Set[Tip]= {
    msgs.fold(Set(), (acc, msg) => acc.setAdd(msg.tip))
  }

  /// Build a TC out of a set of timeout messages
  pure def build_tc(timeouts: Set[TimeoutMsg], addr: Address): TC = {
    // getOnlyElement will throw an error if we have different views
    val view = timeouts.map(t => t.view).getOnlyElement()
    val high_tip = find_high_tip_from_messages(timeouts)
    {
      c: timeouts,
      view: view,
      high_tip: high_tip,
      tips: get_tips_from_timeouts(timeouts),
      sigma: addr,
    }
  }

  /// Build a QC out of a set of votes
  pure def build_qc(votes: Set[VoteMsg], addr: Address, state_hash: StateHash): Option[QC] = {
    // getOnlyElement will throw an error if we have different seqs/views
    if (votes.size() < Q) None
    else
      val seq = votes.map(v => v.seq).getOnlyElement()
      val view = votes.map(v => v.view).getOnlyElement()
      val id = { seq: seq, view: view, byzantine: 0 }
      Some({
        c: votes,
        view: view,
        seq: seq,
        proposal_id: id,
        state_hash: state_hash,
        sigma: addr,
      })
  }


  /// Execute the proposal
  /// TODO: This is fine as it is, but we should think if we can do better here.
  pure def execute_block(ledger: Ledger, p: Proposal): Ledger = {
    ledger.append(p)
  }

  /// Check if a proposal conflicts with the ledger
  pure def proposal_conflicts(ledger: Ledger, p: Proposal, ancestors: ProposalID -> Set[ProposalID]): bool = {
    ledger.toSet().exists(l => conflicting_props(l, p, ancestors))
  }

  /// Revert the ledger back to the latest ancestor of p that is in the ledger.
  /// `ancestors` maps each proposalID to the full set of its ancestor‐IDs.
  pure def revert_ledger(ledger: Ledger, p: Proposal, ancestors_mock: AncestorsMock): Ledger = {
    // 1) Look up the set of all ancestor IDs for p
    pure val ancIds = ancestors_mock.fetch_ancestors(p.proposal_id)

    // 2) Walk the ledger and remember the last index where we saw one of those IDs
    //  foldl((nextIndex, lastMatch), ((idx, foundIdx), elem )) =>
    //    if elem.proposal_id ∈ ancIds then (idx+1, idx) else (idx+1, foundIdx)
    pure val result = ledger.foldl((0, -1), (acc, elem) => {
      pure val idx = acc._1
      pure val foundIdx = acc._2
      if (elem.proposal_id.in(ancIds))
        (idx + 1, idx)
      else
        (idx + 1, foundIdx)
    })

    val lastIdx = result._2

    // 3) If we never found a match (lastIdx == -1), just return an empty ledger
    //  otherwise slice up through that index (inclusive)
    if (lastIdx < 0) {
      List()
    } else {
      ledger.slice(0, lastIdx + 1)
    }
  }

  //
  // Algorithm 1 (page 13)
  // Utilities for a validator
  //

  /// Alg 1, line 1
  /// Form a block out of a QC and a payload
  pure def build_block(qc: QC, payload: str): Block =
    {
      seq: qc.seq + 1,
      payload: payload,
      payload_hash: hash(payload),
      qc: qc,
      block_hash: hash_block(qc.seq + 1, hash(payload), qc),
    }

  /// Algorithm 1, page 13 (line 6)
  /// Form a proposal out of a block and a set of certificates
  pure def build_proposal(
    view: int,
    block: Block,
    tc: Option[TC],
    nec: Option[NEC],
    addr: Address
  ): Proposal = {
    val id = { seq: block.seq, view: view, byzantine: 0 }
    {
      view: view,
      proposal_id: id,
      block: block,
      sigma: addr,
      tc: tc,
      nec: nec,
    }
  }

  /// Alg 1, line 10
  /// Confirm the proposal continues from the last certified block.
  /// It then accepts proposals made under normal operation, when the leader advances without any timeouts.
  /// In recovery after a timeout, it only accepts either the reproposal of the highest‐tip block or,
  /// if that block couldn’t be recovered, a new block justified by a No‑Endorsement Certificate.
  pure def safety_check(p: Proposal): bool = {
    if (p.block.seq != p.block.qc.seq + 1) // Warning: typo in the paper (line 11)
      false
    else if (p.view == p.block.qc.view + 1)
      true
    else if (p.tc != None and p.view == p.tc.unwrap().view + 1)
      pure val p_tc = p.tc.unwrap()
      if (p.block.qc != p_tc.high_tip.unwrap().block_header.qc
          or p_tc.high_tip != find_high_tip_from_tc(p_tc))
        false
      else if (p.nec != None)
        p.nec.unwrap().view == p.view and p.nec.unwrap().highqc_view == p.block.qc.view
      else
        p.block.block_hash == p_tc.high_tip.unwrap().block_header.block_hash
      else
        false
  }

  /// Alg 1 line 22
  pure def update_tip(p: Proposal): Option[Tip] = {
    if (p.view == p.block.qc.view + 1 or p.nec != None)
      Some({
        view: p.view,
        proposal_id: p.proposal_id,
        block_header: p.block.header_from_block(),
        sigma: p.sigma,
        nec: p.nec,
      })
    else
      // Warning: why is there no check for none TC?
      find_high_tip_from_tc(p.tc.unwrap())
  }

  /// Alg 1 line 26
  pure def parent_id(p: Proposal): ProposalID =
    p.block.qc.proposal_id

  //
  // Algorithm 3 (page 16)
  // Finding high tip from a tc or set of timeout messages
  //

  /// Alg 3 line 11
  /// Returns true only if a tip represents a “fresh” proposal:
  ///   - A happy‑path proposal where tip.view == tip.block.qc.view+1, or
  ///   - A NEC‑driven proposal where tip.nec.view == tip.view && tip.nec.highqc_view == tip.block.qc.view
  pure def verify_fresh_proposal(tip: Tip): bool ={
    if (tip.view == tip.block_header.qc.view + 1)
      true
    else
      match tip.nec {
        | None => false
        | Some(nec) =>
          tip.view == nec.view and tip.block_header.qc.view == nec.highqc_view
      }
  }

  /// Alg 3 line 1
  /// Gathers all validator tips from a timeout certificate or timeout messages.
  ///   - It aborts and returns nil if any tip fails the fresh‑proposal checks.
  ///   - Otherwise, it picks and returns the tip with the highest view number.
  /// Warning: the side effects of this function in the pseudocode seem wrong, why are we updating the stored TC to None at the start?
  pure def find_high_tip(tips: Set[Tip]): Option[Tip] = {
    // The first if else block (L3 -> L7) is skipped because we implemented a separate function for sets of timeout messages (find_high_tip_from_messages).
    if (tips.exists(t => not(t.verify_fresh_proposal())))
      None
    else
      // argmax (t ∈ tips) t.view
      // Returns None if tips is empty
      tips.fold(None, (acc, t) => {
        match acc {
          | None => Some(t)
          | Some(h) => if (t.view > h.view) Some(t) else acc
        }
      })
  }

  /// Alg 3 line 1
  /// find_high_tip() for a timeout certificate
  pure def find_high_tip_from_tc(tc: TC): Option[Tip] = {
    find_high_tip(tc.tips)
  }

  /// Alg 3 line 1
  /// find_high_tip() for a set of timeout messages.
  pure def find_high_tip_from_messages(msgs: Set[TimeoutMsg]): Option[Tip] = {
    find_high_tip(get_tips_from_timeouts(msgs))
  }

  //
  // Algorithm 4 (page 22)
  // Pacemaker for View Synchronization
  //

  /// Alg 4 line 2 / Alg 4 line 6
  /// Update the local state with a new view.
  /// We pass view instead of cert to simplify the code.
  pure def increment_view(view: int, s: LocalState): Transition = {
    if (view >= s.curView)
      // Increment view to next and reset the timer, old timers are discarded at apply_effect
      { post_state: { ...s, curView: view + 1 }, effects: Set(choreo::TriggerEvent(TimeoutEvent(view + 1))) }
    else
      // If we are already in a higher view, we do not change the state.
      noop(s)
  }


  /// Alg 2 line 49
  /// As opposed to the paper, we write the timeout event as a function that is called by the timeout handler.
  /// Instead of of a "upon" statement that gets triggered.
  /// Warning: The upon trigger event block is not clear on its synchrony assumptions.
  pure def trigger_timeout_event(s: LocalState): Transition = {
    pure val timeout_msg = {
      view: s.curView,
      // TODO: check if this is safe, it is not specified in the paper, made me think it is an option (Line 50)
      tip: s.tip.unwrap(),
      tc: { view: s.curView, high_tip: None, tips: Set(), sigma: s.process_id },
      sigma: s.process_id
    }

    {
      post_state: { ...s, highest_voted_view: max(s.highest_voted_view, s.curView) },
      effects: Set(
        choreo::Broadcast(Timeout(timeout_msg)),
        choreo::CustomEffect(LogMessage(Timeout(timeout_msg)))
      )
    }
  }

  pure def handle_proposal(
    ls: LocalState,
    p: Proposal,
    props_mock: ProposalsMock,
    ancestors_mock: AncestorsMock,
  ): Transition = {
    match p.tc {
      | None => noop(ls)
      | Some(tc) => increment_view(tc.view, ls)
    }.and_then(s => {
      increment_view(p.block.qc.view, s)
    }).and_then(s => {
      // Warning: is the view being updated before the Leader check? Lines 35-36.
      if (p.view != s.curView or not (is_leader(s, p.sigma))) noop(s) else

      // Warning: The view being updated before the safety check.
      if (not(safety_check(p) and p.view > max(s.highest_voted_view, p.block.qc.view))) noop(s) else

      // Line 38
      pure val parent_proposal = props_mock.fetch(p.parent_id())

      // Line 41
      pure val commit = if (p.block.qc.view == parent_proposal.block.qc.view + 1)
        pure val grandparent_proposal = props_mock.fetch(parent_proposal.parent_id())
        Set(
          choreo::CustomEffect(LogCommit((ls.process_id, grandparent_proposal))),
          choreo::CustomEffect(Confirmation(p)),
        )
      else
        Set()

      // Line 43
      pure val early_confirmation = if (p.view == p.block.qc.view + 1) // Warning: typo in the paper
        Set(choreo::CustomEffect(EarlyConfirmation(parent_proposal)))
      else
        Set()

      // Line 44 - If ledger conflicts with parent proposal, revert to the common ancestor.
      pure val reverted_ledger = if (proposal_conflicts(s.ledger, parent_proposal, ancestors_mock))
        revert_ledger(s.ledger, parent_proposal, ancestors_mock)
      else
        s.ledger

      // Line 45 - Speculate
      pure val ledger = if (p.view == p.block.qc.view + 1)
        execute_block(reverted_ledger, parent_proposal)
      else
        reverted_ledger

      pure val vote_msg = {
        view: p.view,
        seq: p.block.seq,
        proposal_id: p.proposal_id,
        state_hash: state_hash(s),
        sigma: s.process_id,
      }

      pure val next_leader = leader_from_view(p.view + 1)
      pure val send_vote = Set(
        choreo::Send({ to: next_leader, message: Vote(vote_msg) }),
        choreo::CustomEffect(LogMessage(Vote(vote_msg)))
      )

      {
        post_state: { ...s, highest_voted_view: p.view, ledger: ledger, tip: update_tip(p) },
        effects: commit.union(early_confirmation).union(send_vote)
      }
    })
  }

  pure def acc_timeouts(
    ls: LocalState,
    timeouts: Set[TimeoutMsg]
  ): Transition =
    timeouts.fold(noop(ls), (tr, t) => {
      tr
        .and_then(s => increment_view(t.tip.block_header.qc.view, s))
        .and_then(s => increment_view(t.tip.view, s))
    })

  pure def handle_timeout(s: LocalState, timeout: TimeoutMsg): (Transition, Option[TC]) = {
    // Check if we have a quorum
    val v = timeout.view
    if (v < s.curView) (noop(s), None) else

    pure val res = increment_view(timeout.tip.block_header.qc.view, s)
      .and_then(s => increment_view(timeout.tip.view, s))

    // Timeout is new, let's accumulate it
    val acc_timeouts = res.post_state.timeouts.getOrElse(v, Set()).setAdd(timeout)
    val updated_state = res.post_state.add_timeouts(v, acc_timeouts)

    // Check if we have a quorum
    val res2 = if (acc_timeouts.size() >= Q) {
      val tc = build_tc(acc_timeouts, updated_state.process_id)
      (increment_view(tc.view, updated_state), Some(tc))
    } else if (acc_timeouts.size() >= F + 1 and not(res.post_state.timeouts_already_broadcast.contains(v))) {
      // TRIGGER TIMEOUT EVENT
      (updated_state.mark_already_broadcast_timeout(v).trigger_timeout_event(), None)
    } else {
      (noop(updated_state), None)
    }

    (join_results(res, res2._1), res2._2)
  }


  //------------------------------------------ Transition Listeners ------------------------------------------

  pure def upon_proposal_msg(
    ctx: LocalContext,
    proposal: Proposal
  ): Set[Transition] = {
    val props_mock = ctx.extensions.proposals_mock
    val ancestors_mock = ctx.extensions.ancestors_mock
    Set(handle_proposal(ctx.state, proposal, props_mock, ancestors_mock))
  }

  /// Alg 2 line 10 / line 52 (leader/ non-leader)
  pure def upon_timeout_msg(ctx: LocalContext, t: TimeoutMsg): Set[Transition] = {
    pure val res = handle_timeout(ctx.state, t)
    pure val tc = res._2

    Set(res._1.and_then(s => {
      // line 52 (non-leader)
      if (not(s.am_i_leader())) noop(s) else

      // line 11 (leader)

      // Not enough timeout messages to form tc
      if (tc == None) noop(s) else {
        val updated_state = { ...s, last_tc: tc, high_tip: tc.unwrap().high_tip }
        // TODO: it should be safe to unwrap here, but we should check.
        val high_tip = tc.unwrap().high_tip.unwrap()

        // if block and its payload (block.payload) for high tip is present
        if (block_present(ctx.extensions.proposals_mock ,high_tip.block_header)) {
          // Line 17
          val block = get_present_block(ctx.extensions.proposals_mock, high_tip.block_header)
          val p = build_proposal(updated_state.curView, block, tc, None, updated_state.process_id)
          {
            post_state: updated_state,
            effects: Set(
              choreo::Broadcast(Prop(p)),
              choreo::CustomEffect(LogProposal(p))
            )
          }
        } else {
          // Line 18-19-20 recoveringcurView ← true; SendRecoveryRequest(curView, high tip, tc);
          // TODO: For the moment this is replaced by fetching the block from the DA variable for debugging purposes
          val block = get_present_block(ctx.extensions.proposals_mock, high_tip.block_header)
          val p = build_proposal(updated_state.curView, block, tc, None, updated_state.process_id)
          {
            post_state: updated_state,
            effects: Set(
              choreo::Broadcast(Prop(p)),
              choreo::CustomEffect(LogProposal(p))
            )
          }
        }
      }
    }))
  }

  /// Alg 4 line 25
  pure def handle_vote(vote: VoteMsg, s: LocalState): (Transition, Option[QC]) = {
    val v = vote.view
    val id = vote.proposal_id

    if (v < s.curView) (noop(s), None) else

    // Vote is new, let's accumulate it
    val acc_votes = s.votes.getOrElse(id, Set()).setAdd(vote)
    val updated_state = s.add_votes(id, acc_votes)

    // Check if we have a quorum
    if (acc_votes.size() >= Q) {
      val qc = build_qc(acc_votes, updated_state.process_id, state_hash(updated_state))
      if (qc == None) (noop(updated_state), None) else
      (increment_view(qc.unwrap().view, updated_state), qc)
    } else {
      (noop(updated_state), None)
    }
  }

  //
  // Algorithm 2 (page 15)
  // Consensus for Validator i
  //

  /// Alg 2 line 3 (Only for the leader)
  pure def upon_vote_msg(ctx: LocalContext, v: VoteMsg): Set[Transition] = {
    //if (not(s.i_am_leader())) noop(s) else
    // Line 3
    pure val r = handle_vote(v, ctx.state)
    pure val res = r._1
    pure val qc = r._2
    if (not(res.post_state.am_i_leader())) Set() else
      Set(res.and_then(s => {
        if (qc == None) noop(s) else
        val new_block = build_block(qc.unwrap(), BLOCK_PAYLOAD)
        val p = build_proposal(s.curView, new_block, None, None, s.process_id)
        {
          post_state: s,
          effects: Set(
            choreo::Broadcast(Prop(p)),
            choreo::CustomEffect(LogProposal(p))
          )
        }
      }))
  }

  pure def main_listener(ctx: LocalContext, input: Input): Set[Transition] = {
    match input {
      | Message(m) => {
        // Process a message
        match m {
          | Prop(p) => upon_proposal_msg(ctx, p)
          | Vote(v) => upon_vote_msg(ctx, v)
          | Timeout(t) => upon_timeout_msg(ctx, t)
        }
      }
      | Event(e) => {
        // Process a timeout
        match e {
          | TimeoutEvent(data) => Set(trigger_timeout_event(ctx.state))
        }
      }
    }
  }

  // ------------------------------------------- Effect Application -------------------------------------------

  pure def log_message(ctx: GlobalContext, msg: Message): GlobalContext = {
    val ext = ctx.extensions
    val ext1 = { ...ext, logging: { ...ext.logging, msgHistory: ext.logging.msgHistory.setAdd(msg) } }

    { ...ctx, extensions: ext1 }
  }

  pure def log_commit(ctx: GlobalContext, v: Address, p: Proposal): GlobalContext = {
    val ext = ctx.extensions
    val ext1 = { ...ext, logging: {
      ...ext.logging,
      committed_proposals: ext.logging.committed_proposals.setBy(v, s => s.setAdd(p))
    }}

    { ...ctx, extensions: ext1 }
  }

  pure def save_proposal_to_mocks(ctx: GlobalContext, p: Proposal): GlobalContext = {
    // Abstraction: This was added to provide a data availability layer
    // for the proposals to avoid having missing proposals, and remove the
    // need for a block recovery mechanism.
    // TODO: refactor this when we have a block recovery mechanism.

    val ext = ctx.extensions
    val ext1 = {
      ...ext,
      proposals_mock: ext.proposals_mock.setAdd(p),
      ancestors_mock: ext.ancestors_mock.save_ancestor(p.proposal_id, p.parent_id())
    }

    { ...ctx, extensions: ext1 }
  }

  pure def apply_custom_effect(ctx: GlobalContext, effect: CustomEffects): GlobalContext = {
    match effect {
      | LogMessage(msg) => {
        ctx.log_message(msg)
      }
      | LogProposal(p) => {
        ctx.save_proposal_to_mocks(p).log_message(Prop(p))
      }
      | LogCommit(c) => {
        ctx.log_commit(c._1, c._2)
      }
      | EarlyConfirmation(p) => ctx
      | Confirmation(p) => ctx
    }
  }

  // ------------------------------------------- Initialization & Execution -------------------------------------------

  pure def initialize_process_empty(process_id: Address): LocalState = {
    high_tip: None,
    last_tc: None,
    tip: None,
    timeouts_already_broadcast: Set(),
    curView: 0,
    ledger: [],
    highest_voted_view: -1,
    process_id: process_id,
  }

  // Initialization depends on the instance, so we make it parameterized
  action init_from(initialize_process, initial_messages, initial_extensions) = choreo::init({
    system: validators.mapBy(v => initialize_process(v)),
    messages: validators.mapBy(v => initial_messages),
    events: validators.mapBy(v => Set()),
    extensions: initial_extensions,
  })

  action step = choreo::micro_step(
    main_listener,
    apply_custom_effect
    // displayer,
  )

  // ------------------------------------------- Invariants and Witnesses -------------------------------------------

  /// Accessor
  val logs = choreo::s.extensions.logging

  /// No Tail-Forking (NTF) page 10:
  val ntf =
    val votes = logs.msgHistory.get_votes()
    val committed_proposals = logs.committed_proposals.values().flatten()
    votes.forall(v =>
      // If an honest leader’s proposal for sequence number s is voted upon by a majority of honest validators,
      // TODO: filter faulty proposer's proposals
      votes.filter(v2 => v2.seq == v.seq and v2.proposal_id == v.proposal_id).size() > N / 2
      implies
      // then no other proposal can commit at sequence s.
      committed_proposals.forall(p =>
        p.block.seq == v.seq implies
        (p.proposal_id.seq == v.proposal_id.seq and p.proposal_id.byzantine == v.proposal_id.byzantine))
      )

  /// Safety property page 10: No two correct validators commit different blocks
  /// for the same sequence number
  val safety =
    val ps = logs.committed_proposals.values().flatten()
    ps.forall(p1 => ps.forall(p2 => p1.block.seq == p2.block.seq implies p1 == p2))

  /// Witness: Search for a scenario where a proposal gets reproposed.
  val reproposals =
    val proposals = logs.msgHistory.get_proposals()
    proposals.filter(p =>
      proposals.exists(p2 =>
        p.proposal_id != p2.proposal_id and p.block.seq == p2.block.seq
      )
    )

  val reproposal_w = reproposals.size() == 0

  /// Witness: Search for a scenario where a proposal is committed with a TC.
  val commit_with_tc =
    val ps = logs.committed_proposals.values().flatten()
    ps.exists(p => p.tc != None)

  val commit_with_tc_w = not(commit_with_tc)

  /// Witness: search for a QC that was not followed by a proposal referencing it.
  val missing_qc =
    val votes = logs.msgHistory.get_votes()
    val props = logs.msgHistory.get_proposals()
    // Group views by view and proposal_id
    val grouped_votes = votes.groupBy(v => (v.view, v.proposal_id))
    grouped_votes.values().exists(entry => {
      val view = entry.map(v => v.view).getOnlyElement()
      val quorum = entry.size() >= Q

      val skipped = props.exists(
        p => p.block.qc.view > view
      )

      val not_used = props.forall(
        p => p.block.qc.view != view
      )

      quorum and skipped and not_used and view > 4
    })

  val missing_qc_w = not(missing_qc)

  /// Witness: search for a disappearing TIP.
  val missing_tip =
    val props = logs.msgHistory.get_proposals()
    val tcs = props.filter(p => p.tc != None).map(p => (p.view, p.tc.unwrap()))
    // find a pair of (view, tc)
    tcs.exists(((view1, tc1)) => {
      tc1.high_tip != None
        and tcs.exists(((view2, tc2)) => {
          view1 < view2
            and tc2.high_tip != None
            and tc1.high_tip.unwrap().view > tc2.high_tip.unwrap().view
        })
    })

  val missing_tip_w = not(missing_tip)
}
