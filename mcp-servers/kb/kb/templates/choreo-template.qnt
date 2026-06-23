
module ProtocolName {
  import basicSpells.* from "spells/basicSpells"
  import choreo(processes = NODES) as choreo from "choreo"

  // 1. AUXILIARY TYPES - Protocol-specific types
  type Role = RoleA | RoleB
  type Stage = StageOne | StageTwo | StageFinal

  // 2. MANDATORY CHOREO TYPES
  type Node = str
  type Message =
    | MessageType1(Node)
    | MessageType2
    | MessageType3

  type StateFields = {
    role: Role,
    stage: Stage,
    // Add protocol-specific state fields
  }

  type CustomEffects = ()
  type Event = ()
  type Extensions = ()

  // 3. BOILERPLATE - Copy as-is
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

  // 4. HELPER FUNCTIONS - Extract information from messages
  pure def get_filtered_messages(msgs: Set[Message]): Set[Node] = {
    msgs.filterMap(m => match m {
      | MessageType1(n) => Some(n)
      | _ => None
    })
  }

  // 5. LISTENER FUNCTIONS - One per transition
  /// Description of what this listener does
  pure def listener_name(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == RoleA and ctx.state.stage == StageOne) {
      Set({
        effects: Set(choreo::Broadcast(MessageType2)),
        post_state: { ...ctx.state, stage: StageTwo }
      })
    } else {
      Set()
    }
  }

  /// Another listener
  pure def another_listener(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.role == RoleB and ctx.messages.contains(MessageType2)) {
      Set({
        effects: Set(),
        post_state: { ...ctx.state, stage: StageFinal }
      })
    } else {
      Set()
    }
  }

  // 6. MAIN LISTENER - Combines all listeners
  pure def main_listener(ctx: LocalContext): Set[Transition] = {
    Set(
      listener_name(ctx),
      another_listener(ctx)
      // Add all listeners here
    ).flatten()
  }

  // 7. CONSTANTS - Define nodes and roles
  pure val NODE_A: Node = "nodeA"
  pure val NODE_B: Node = "nodeB"
  pure val NODES = Set(NODE_A, NODE_B)

  // 8. INITIALIZATION FUNCTION
  pure def initialize(n: Node): LocalState = {
    {
      process_id: n,
      role: if (n == NODE_A) RoleA else RoleB,
      stage: StageOne,
      // Initialize other fields
    }
  }

  // 9. STATE MACHINE SETUP
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

  // 10. INVARIANTS - Properties that should always hold
  val consistency = NODES.forall(n1 => {
    NODES.forall(n2 => {
      not(choreo::s.system.get(n1).stage == StageFinal
        and choreo::s.system.get(n2).stage == StageOne)
    })
  })

  // 11. WITNESSES - For testing listener reachability
  val wit_reaches_final = NODES.exists(n =>
    choreo::s.system.get(n).stage != StageFinal
  )

  // 12. TESTING HELPER - For controlled execution
  action step_with(v: Node, listener: LocalContext => Set[Transition]): bool =
    choreo::step_with(v, listener, (c, _) => c)
}
