
module two_phase_commit {
  import basicSpells.* from "./spells/basicSpells"
  import choreo(processes = NODES) as choreo from "./choreo"

  // Auxiliary types
  type Role = Coordinator | Participant
  type Stage = Working | Prepared | Committed | Aborted

  // Mandatory types for the Choreo
  type Node = str
  type Message =
    | CoordinatorAbort
    | CoordinatorCommit
    | ParticipantPrepared(Node)

  type StateFields = {
    role: Role,
    stage: Stage,
  }

  type CustomEffects = ()
  type Event = ()
  type Extensions = ()

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
  /* End of boilerplate */

  pure def get_prepared_msgs(msgs: Set[Message]): Set[Node] = {
    msgs.filterMap(m => match m {
      | ParticipantPrepared(n) => Some(n)
      | _ => None
    })
  }

  // --- Participant transitions ----------------------------------------------
  pure def spontaneously_prepares(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Participant and ctx.state.stage == Working) {
      Set({
        effects: Set(choreo::Broadcast(ParticipantPrepared(ctx.state.process_id))),
        post_state: { ...ctx.state, stage: Prepared }
      })
    } else {
      Set()
    }
  }

  pure def spontaneously_aborts(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Participant and ctx.state.stage == Working) {
      Set({
        effects: Set(),
        post_state: { ...ctx.state, stage: Aborted }
      })
    } else {
      Set()
    }
  }

  pure def aborts_as_instructed(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Participant and ctx.messages.contains(CoordinatorAbort)) {
      Set({
        effects: Set(),
        post_state: { ...ctx.state, stage: Aborted }
      })
    } else {
      Set()
    }
  }

  pure def commits_as_instructed(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Participant and ctx.messages.contains(CoordinatorCommit)) {
      Set({
        effects: Set(),
        post_state: { ...ctx.state, stage: Committed }
      })
    } else {
      Set()
    }
  }

  // --- Coordinator transitions ------------------------------
  pure def decides_on_commit(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Coordinator
        and ctx.state.stage == Working
        and ctx.messages.get_prepared_msgs().size() == PARTICIPANTS.size()) {
      Set({
        effects: Set(choreo::Broadcast(CoordinatorCommit)),
        post_state: { ...ctx.state, stage: Committed }
      })
    } else {
      Set()
    }
  }

  pure def decides_on_abort(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == Coordinator and ctx.state.stage == Working) {
      Set({
        effects: Set(choreo::Broadcast(CoordinatorAbort)),
        post_state: { ...ctx.state, stage: Aborted }
      })
    } else {
      Set()
    }
  }

  pure def main_listener(ctx: LocalContext): Set[Transition] = {
    Set(
      spontaneously_prepares(ctx),
      spontaneously_aborts(ctx),
      aborts_as_instructed(ctx),
      commits_as_instructed(ctx),
      decides_on_commit(ctx),
      decides_on_abort(ctx)
    ).flatten()
  }

  pure val COORDINATOR: Node = "c"
  pure val PARTICIPANTS: Set[Node] = Set("p1", "p2", "p3")
  pure val NODES = PARTICIPANTS.union(Set(COORDINATOR))

  pure def initialize(n: Node): LocalState = {
    {
      process_id: n,
      role: if (n == COORDINATOR) Coordinator else Participant,
      stage: Working,
    }
  }

  // Setting up the state machine

  action init = choreo::init({
    system: NODES.mapBy(n => initialize(n)),
    messages: NODES.mapBy(n => Set()),
    events: NODES.mapBy(n => Set()),
    extensions: ()
  })

  action step = choreo::step(
    main_listener,
    (c, _) => c
  )

  // Invariants and witnesses

  val consistency = PARTICIPANTS.forall(p1 => {
    PARTICIPANTS.forall(p2 => {
      not(choreo::s.system.get(p1).stage == Committed
        and choreo::s.system.get(p2).stage == Aborted)
    })
  })

  val wit_commit = PARTICIPANTS.exists(p => choreo::s.system.get(p).stage != Committed)

  action step_with(v: Node, listener: LocalContext => Set[Transition]): bool =
    choreo::step_with(v, listener, (c, _) => c)

  run commitTest = init
    .then(step_with("p1", spontaneously_prepares))
    .then(step_with("p2", spontaneously_prepares))
    .then(step_with("p3", spontaneously_prepares))
    .then(step_with(COORDINATOR, decides_on_commit))
    .then(step_with("p1", commits_as_instructed))
    .then(step_with("p2", commits_as_instructed))
    .then(step_with("p3", commits_as_instructed))
    .expect({
      // Check that all participants have committed
      PARTICIPANTS.forall(p => {
        choreo::s.system.get(p).stage == Committed
      })
    })
}
