module tendermint {
  import basicSpells.* from "./spells/basicSpells"
  import rareSpells.* from "./spells/rareSpells"
  import choreo(processes = NODES) as choreo from "./choreo"

  type Round = int
  type Height = int
  type Stage = ProposeStage | PreVoteStage | PreCommitStage | DecidedStage
  type Value = str

  type Bookkeeping = {
    evidence_propose: Set[ProposeMsg],
    evidence_prevote: Set[PreVoteMsg],
    evidence_precommit: Set[PreVoteMsg],
  }

  type TimeoutKind = ProposeTimeout | PreVoteTimeout | PreCommitTimeout
  type TimeoutEvent = { kind: TimeoutKind, round: Round }

  /// The ID of a value. In the implementation, this would be a hash of the value.
  /// Here, we wrap it in a record and don't convert it back into a value.
  /// This keeps the property that v1.id() == v2.id() iff v1 == v2.
  type ValueId = { hashed: Value }
  type Node = str

  type StateFields = {
    round: Round,
    stage: Stage,
    decision: Option[Value],
    locked_value: Option[Value],
    locked_round: Round,
    valid_value: Option[Value],
    valid_round: Round,
    after_prevote_for_first_time: bool,
    precommit_quorum: bool,
    process_id : Node,
    decisions: Round -> Option[Value],
    proposals: Set[ProposeMsg],
    prevotes: Set[PreVoteMsg],
    precommits: Set[PreVoteMsg],
  }

  type ProposeMsg = {
    src: Node,
    round: Round,
    proposal: Value,
    valid_round: Round,
  }

  type PreVoteMsg = {
    src: Node,
    round: Round,
    id: Option[ValueId],
  }

  type Message =
    | Propose(ProposeMsg)
    | PreVote(PreVoteMsg)
    | PreCommit(PreVoteMsg)

  type CustomEffects =
    | CollectEvidence(Message)

  type Event = TimeoutEvent
  type Extensions = Bookkeeping

  /* Boilerplate */
  type LocalState = choreo::LocalState[Node, StateFields]
  type LocalContext = choreo::LocalContext[Node, StateFields, Message, Event, Extensions]
  type Transition = choreo::Transition[Node, StateFields, Message, Event, CustomEffects]
  type GlobalContext = choreo::GlobalContext[
    Node,
    StateFields,
    Message,
    Event,
    Extensions
  ]
  type Input = choreo::Input[Message, Event]
  /* End of boilerplate */

  pure def get_proposals(s: LocalState): Set[ProposeMsg] =
    s.proposals

  /// All received PreVotes with a given round and value id
  pure def get_prevotes(s: LocalState, round: Round, id: Option[ValueId]): Set[PreVoteMsg] =
    s.prevotes.filter(p => p.round == round and p.id == id)

  pure def get_all_prevotes(s: LocalState): Set[PreVoteMsg] =
    s.prevotes

  /// All received PreCommits
  pure def get_all_precommits(s: LocalState): Set[PreVoteMsg] =
    s.precommits

  /// All received PreCommits with a given round and value id
  pure def get_precommits(s: LocalState, round: Round, id: ValueId): Set[PreVoteMsg] =
    s.precommits.filter(p => p.round == round and p.id == Some(id))


  pure def valid(v: Value): bool = 
    VALID_VALUES.contains(v)

  /// A value hash in an abstract way.
  pure def id(v: Value): ValueId = { hashed: v }

  pure def start_round(input: LocalContext, round: Round): Set[Transition] = {
    if (round > MAX_ROUND) Set() else
    pure val s1 = { 
      ...input.state,
      round: round,
      stage: ProposeStage,
      precommit_quorum: false
    }

    if (s1.process_id == PROPOSER.get(round)) {
      pure val proposal = if (s1.valid_value != None) s1.valid_value.unwrap() else VALUES.get(round)
      Set({
        post_state: s1,
        effects: Set(
          choreo::Broadcast(
            Propose({ src: s1.process_id, round: s1.round, proposal: proposal, valid_round: s1.valid_round })
          )
        ),
      })
    } else {
      Set({
        post_state: s1,
        effects: Set(
          choreo::TriggerEvent({ kind: ProposeTimeout, round: s1.round })
        ),
      })
    }
  }
  
  pure def process_proposal_at_propose_stage(input: LocalContext, msg: ProposeMsg): Set[Transition] = {
    pure val s = input.state

    pure val upon_condition = and {
      // upon <PROPOSAL, hp , roundp , v, −1>
      msg.valid_round == -1,
      // from proposer(hp, roundp)
      msg.src == PROPOSER.get(s.round),
      // while stepp = propose
      s.stage == ProposeStage,
    }
    if (not(upon_condition)) Set() else

    pure val broadcast =
      if (msg.proposal.valid() and (s.locked_round == -1 or s.locked_value == Some(msg.proposal)))
        choreo::Broadcast(PreVote({ src: s.process_id, round: s.round, id: Some(msg.proposal.id()) }))
      else
        choreo::Broadcast(PreVote({ src: s.process_id, round: s.round, id: None }))

    Set({
      post_state: { ...s, stage: PreVoteStage, after_prevote_for_first_time: true },
      effects: Set(
        broadcast,
        choreo::CustomEffect(CollectEvidence(Propose(msg)))
      )
    })
  }  

  pure def process_proposal_and_quorum_at_propose_stage(input: LocalContext, msg: ProposeMsg): Set[Transition] = {
    pure val s = input.state
    pure val prevotes = s.get_prevotes(msg.valid_round, Some(msg.proposal.id()))

    pure val upon_condition = and {
      // upon <PROPOSAL, hp , roundp , v, vr>
      // from proposer(hp, roundp)
      msg.src == PROPOSER.get(s.round),
      // AND 2f + 1 <PREVOTE, hp , vr, id(v)>
      prevotes.map(m => m.src).size() >= 2 * F + 1,
      // while stepp = propose
      s.stage == ProposeStage,
      // ∧ (vr ≥ 0 ∧ vr < roundp)
      msg.valid_round >= 0 and msg.valid_round < s.round,
    }
    if (not(upon_condition)) Set() else

    pure val broadcast =
      if (msg.proposal.valid() and (s.locked_round <= msg.valid_round or s.locked_value == Some(msg.proposal)))
        choreo::Broadcast(PreVote({ src: s.process_id, round: s.round, id: Some(msg.proposal.id()) }))
      else
        choreo::Broadcast(PreVote({ src: s.process_id, round: s.round, id: None }))

    Set({
      post_state: { ...s, stage: PreVoteStage, after_prevote_for_first_time: true },
      effects: Set(broadcast, choreo::CustomEffect(CollectEvidence(Propose(msg))))
        .union(prevotes.map(m => choreo::CustomEffect(CollectEvidence(PreVote(m))))),
    })
  }

  pure def process_prevote_quorum_on_prevote_stage(input: LocalContext, msg: PreVoteMsg): Set[Transition] = {
    pure val s = input.state
    pure val prevotes = s.get_all_prevotes().filter(r => r.round == s.round) 

    pure val upon_condition = and {
      // upon 2f + 1 <PREVOTE, hp , roundp , ∗>
      prevotes.map(m => m.src).size() >= 2 * F + 1,
      // while stepp = prevote for the first time
      s.stage == PreVoteStage and s.after_prevote_for_first_time,
    }
    if (not(upon_condition)) Set() else

    Set({
      post_state: { ...s, after_prevote_for_first_time: false },
      effects:
        Set(choreo::TriggerEvent({ kind: PreVoteTimeout, round: msg.round }))
          .union(prevotes.map(m => choreo::CustomEffect(CollectEvidence(PreVote(m))))),
    })
  }
  
  pure def process_proposal_and_quorum_after_prevote_stage_for_the_first_time(
    input: LocalContext,
    msg: ProposeMsg
  ): Set[Transition] = {
    pure val s = input.state
    pure val prevotes = s.get_prevotes(s.round, Some(msg.proposal.id()))

    pure val upon_condition = and {
      // upon <PROPOSAL, hp , roundp , v, ∗>
      // from proposer(hp , roundp)
      msg.src == PROPOSER.get(s.round),
      // AND 2f + 1 <PREVOTE, hp , roundp , id(v)>
      prevotes.map(m => m.src).size() >= 2 * F + 1,
      // while valid(v) ∧ stepp ≥ prevote for the first time
      s.stage.in(Set(PreVoteStage, PreCommitStage)) and s.after_prevote_for_first_time,
    }
    if (not(upon_condition)) Set() else

    pure val base_result = {
      post_state: {
        ...s,
        valid_value: Some(msg.proposal),
        valid_round: s.round,
      },
      effects:
        Set(choreo::CustomEffect(CollectEvidence(Propose(msg))))
          .union(prevotes.map(m => choreo::CustomEffect(CollectEvidence(PreVote(m))))),
    }

    val s2 = base_result.post_state
    if (s2.stage == PreVoteStage)
      Set({
        post_state: { ...s2, locked_value: Some(msg.proposal), locked_round: msg.round, stage: PreCommitStage },
        effects:
          Set(choreo::Broadcast(PreCommit({ src: s2.process_id, round: msg.round, id: Some(msg.proposal.id()) })))
            .union(base_result.effects)
      })
    else
      Set(base_result)
  }


  pure def process_prevote_quorum_at_prevote_stage(input: LocalContext, msg: PreVoteMsg): Set[Transition]= {
    pure val s = input.state
    pure val prevotes = s.get_prevotes(s.round, None)
    pure val upon_condition = and {
      // upon 2f + 1 <PREVOTE, hp , roundp , nil>
      prevotes.map(m => m.src).size() >= 2 * F + 1,
      // while stepp = prevote
      s.stage == PreVoteStage,
    }
    if (not(upon_condition)) Set() else

    Set({
      post_state: { ...s, stage: PreCommitStage },
      effects:
        Set(choreo::Broadcast(PreCommit({ src: s.process_id, round: msg.round, id: None })))
          .union(prevotes.map(m => choreo::CustomEffect(CollectEvidence(PreVote(m))))),
    })
  }

  // line 47
  pure def process_precommit_quorum_for_the_first_time(input: LocalContext, msg: PreVoteMsg): Set[Transition] = {
    pure val s = input.state
    pure val precommits = s.get_all_precommits().filter(r => r.round == s.round)

    pure val upon_condition = and {
      // upon 2f + 1 <PRECOMMIT, hp , roundp , ∗> for the first time
      precommits.map(m => m.src).size() >= 2 * F + 1,
      not(s.precommit_quorum),
    }
    if (not(upon_condition)) Set() else

    Set({
      post_state: { ...s, precommit_quorum: true },
      effects:
        Set(choreo::TriggerEvent({ kind: PreCommitTimeout, round: msg.round }))
          .union(precommits.map(m => choreo::CustomEffect(CollectEvidence(PreCommit(m))))),
    })
  }

  pure def process_proposal_and_precommit_quorum_but_no_decision(input: LocalContext, msg: ProposeMsg): Set[Transition] = {
    pure val s = input.state
    pure val precommits = s.get_precommits(msg.round, msg.proposal.id())

    pure val upon_condition = and {
      // upon <PROPOSAL, hp , r, v, ∗>
      // from proposer(hp , r)
      msg.src == PROPOSER.get(msg.round),
      // AND 2f + 1 <PRECOMMIT, hp , r, id(v)>
      precommits.map(m => m.src).size() >= 2 * F + 1,
      // while decisionp[hp] = nil
      s.decision == None,
    }
    if (not(upon_condition)) Set() else
    if (not(msg.proposal.valid())) Set() else

    Set({
      post_state: {
        ...s,
        decision: Some(msg.proposal),
        stage: DecidedStage,
      },
      effects:
        Set(choreo::CustomEffect(CollectEvidence(Propose(msg))))
          .union(precommits.map(m => choreo::CustomEffect(CollectEvidence(PreCommit(m))))),
    })
  }

  pure def receive_message(input: LocalContext, m: Message): Set[Transition] = {
    match m {
      | Propose(msg) => {
        val s = { ...input.state, proposals: input.state.proposals.setAdd(msg) }
        val updated_input = { ...input, state: s }

        pure val results = Set(
          process_proposal_at_propose_stage(updated_input, msg),
          process_proposal_and_quorum_at_propose_stage(updated_input, msg),
          process_proposal_and_quorum_after_prevote_stage_for_the_first_time(updated_input, msg),
        ).flatten()

        if (results.size() > 0) results else Set({ post_state: s, effects: Set() })
      }

      | PreVote(msg) => {
        pure val s = { ...input.state, prevotes: input.state.prevotes.setAdd(msg) }
        pure val updated_input = { ...input, state: s }

        pure val results = Set(
          process_prevote_quorum_on_prevote_stage(updated_input, msg),
          process_prevote_quorum_at_prevote_stage(updated_input, msg),
        ).flatten()

        if (results.size() > 0) results else Set({ post_state: s, effects: Set() })
      }

      | PreCommit(msg) => {
        pure val s = { ...input.state, precommits: input.state.precommits.setAdd(msg) }
        pure val updated_input = { ...input, state: s }

        pure val results = process_precommit_quorum_for_the_first_time(updated_input, msg)

        if (results.size() > 0) results else Set({ post_state: s, effects: Set() })
      }
    }
  }

  pure def handle_timeout(input: LocalContext, t: TimeoutEvent): Set[Transition] = {
    val s = input.state
    match t.kind {
      | ProposeTimeout => {
        // line 55
        if (s.round != t.round or s.stage != ProposeStage) Set() else

        Set({
          post_state: { ...s, stage: PreVoteStage },
          effects: Set(
            choreo::Broadcast(PreVote({ src: s.process_id, round: s.round, id: None })),
            choreo::TriggerEvent({ kind: PreVoteTimeout, round: s.round }),
          )
        })
      }
      | PreVoteTimeout => {
        // line 61
        if (s.round != t.round or s.stage != PreVoteStage) Set() else

        Set({
          post_state: { ...s, stage: PreCommitStage },
          effects: Set(
            choreo::Broadcast(PreCommit({ src: s.process_id, round: s.round, id: None })),
            choreo::TriggerEvent({ kind: PreCommitTimeout, round: s.round }),
          )
        })
      }
      | PreCommitTimeout => {
        // line 65
        if (s.round != t.round) Set() else

        input.start_round(s.round + 1)
      }
    }
  }

  pure def main_listener(ctx: LocalContext, input: Input): Set[Transition] = {
    match input {
      | Message(m) => {
        // Process a message
        receive_message(ctx, m)
      }
      | Event(t) => {
        // Process a timeout
        handle_timeout(ctx, t)
      }
    }
  }

  pure def apply_custom_effect(
    env: GlobalContext,
    effect: CustomEffects
  ): GlobalContext = {
    match effect {
      | CollectEvidence(msg) => {
        val b = env.extensions
        val new_b = match msg {
          | Propose(p)   => { ...b, evidence_propose: b.evidence_propose.setAdd(p) }
          | PreVote(p)   => { ...b, evidence_prevote: b.evidence_prevote.setAdd(p) }
          | PreCommit(p) => { ...b, evidence_precommit: b.evidence_precommit.setAdd(p) }
        }
        { ...env, extensions: new_b }
      }
    }
  }

  // -------------------------------- initialization --------------------------------
  pure val initial_message =
    Propose({ src: PROPOSER.get(0), round: 0, proposal: VALUES.get(0), valid_round: -1 })

  pure val initial_bookkeeping = {
    evidence_propose: Set(),
    evidence_prevote: Set(),
    evidence_precommit: Set(),
  }

  pure def initialize_process(n: Node): LocalState = {
    {
      process_id: n,
      round: 0,
      stage: ProposeStage,
      decision: None,
      locked_value: None,
      locked_round: -1,
      valid_value: None,
      valid_round: -1,
      after_prevote_for_first_time: false,
      precommit_quorum: false,
      decisions: 0.to(6).mapBy(_ => None),
      proposals: Set(),
      prevotes: Set(),
      precommits: Set(),
    }
  }

  // Card(powset)= 4096
  val byzantine_messages_1 = {
    val rounds = Set(0) 
    val byzantine_proposals = rounds.map(r => {
      tuples(FAULTY, Set("v0","v1","v2"), rounds.setAdd(-1)).map(((f, v, vr)) => {
        Propose({ src: f, round: r, proposal: v, valid_round: vr })
      })
    }).flatten()

    val byzantine_prevotes = rounds.map(r => {
      tuples(FAULTY, Set("v0","v1","v2")).map(((f, v)) => {
        PreVote({ src: f, round: r, id: Some(v.id()) })
      })
    }).flatten()

    val byzantine_precommits = rounds.map(r => {
      tuples(FAULTY, Set("v0","v1","v2")).map(((f, v)) => {
        PreCommit({ src: f, round: r, id: Some(v.id()) })
      })
    }).flatten()

    // Reintegrate byzantine proposals
    Set(byzantine_prevotes, byzantine_precommits, byzantine_proposals).flatten()
  }
    
  val byzantine_messages = {
    // We can have at most 2^F faulty nodes, so we take the powerset of the byzantine messages
    // to simulate all possible combinations of byzantine messages.

    // 10 dummy prevotes for future rounds
    val dummy_prevotes = 1000.to(1025).map(r => {
        PreVote({ src: "p4", round: r, id: None })
    })
    dummy_prevotes
    //Set()
  }

  action init = choreo::init({
    system: NODES.mapBy(n => initialize_process(n)),
    messages: NODES.mapBy(n => Set(initial_message).union(byzantine_messages_1)),
    events: NODES.mapBy(n => Set()),
    extensions: initial_bookkeeping
  })

  action step = choreo::micro_step(
    main_listener,
    apply_custom_effect
  )

  val s = choreo::s

  val correct_nodes = s.system.values().filter(s => s.process_id.in(CORRECT))
  /// Agreement: no two correct full nodes decide differently.
  val agreement = tuples(correct_nodes, correct_nodes).forall(((p1, p2)) => {
    p1.decision == None or p2.decision == None or p1.decision == p2.decision
  })

  val validity = correct_nodes.forall(s => s.decision.in(VALID_VALUES.map(v => Some(v)).setAdd(None)))

  // Witnesses
  val one_decided = not(s.system.values().forall(v => v.decision == None))
  val all_decided = not(correct_nodes.exists(v => v.decision == None))

  // Witness for a to find a case where a node is in the decided stage while another is prevote
  // state
  val stages =
    and {
      s.system.values().map(v => v.stage).contains(ProposeStage),
      s.system.values().map(v => v.stage).contains(DecidedStage),
      s.system.values().map(v => v.stage).contains(PreCommitStage),
      s.system.values().map(v => v.stage).contains(PreVoteStage)
    }

  /* CONSTANTS */
  /// An upper bound on the number of Byzantine processes
  const F: int
  /// The set of correct processes
  const CORRECT: Set[Node]
  /// The set of faulty processes
  const FAULTY: Set[Node]
  /// Which node is the proposer in each round
  const PROPOSER: Round -> Node
  /// Which value is proposed in each round.
  /// Values from rounds with correct nodes (in PROPOSER) are considered valid values.
  const VALUES: Round -> Value
  const MAX_ROUND: Round // The maximum round we want to simulate

  /// The set of all nodes
  pure val NODES = CORRECT.union(FAULTY)
  /// The set of all rounds (prepared by the constants)
  pure val ROUNDS = VALUES.keys()
  /// The set of all correct values (prepared by the constants)
  //pure val VALID_VALUES = ROUNDS.filter(k => PROPOSER.get(k).in(CORRECT)).map(k => VALUES.get(k))
  pure val VALID_VALUES = Set("v0","v1", "v2")
}

module valid {
  import tendermint(
    F = 1,
    CORRECT = Set("p1", "p2", "p3"),
    FAULTY = Set("p4"),
    PROPOSER = Map(0 -> "p1", 1 -> "p2", 2 -> "p3", 3 -> "p4"),
    VALUES =  Map(0 -> "v0", 1 -> "v1", 2 -> "v2", 3 -> "v3"),
    MAX_ROUND = 3
  ).*
}

module no_agreement {
  import tendermint(
    F = 1,
    CORRECT = Set("p2", "p3"),
    FAULTY = Set("p1","p4"),
    PROPOSER = Map(0 -> "p1", 1 -> "p2", 2 -> "p3", 3 -> "p4"),
    VALUES =  Map(0 -> "v0", 1 -> "v1", 2 -> "v2", 3 -> "v3"),
    MAX_ROUND = 3
  ).*
}

