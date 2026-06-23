
module utils {
  import basicSpells.* from "./spells/basicSpells"
  import types.* from "types"

  pure def noop(s: LocalState): Transition = {
    { post_state: s, effects: Set() }
  }

  pure def join_results(
    t1: Transition,
    t2: Transition
  ): Transition = {
    { post_state: t2.post_state, effects: t1.effects.union(t2.effects) }
  }

  pure def and_then(
    t: Transition,
    f: LocalState => Transition
  ): Transition =
    join_results(t, f(t.post_state))

  pure def and_then_state(
    state: LocalState,
    f: LocalState => r
  ): r = f(state)

  pure def groupBy(s: Set[a], keyFunc: a => k): k -> Set[a] = {
    s.fold(Map(), (acc, elem) => {
      val key = keyFunc(elem)
      val existing = acc.getOrElse(key, Set())
      acc.put(key, existing.setAdd(elem))
    })
  }

  pure def get_proposals(messages: Set[Message]): Set[Proposal] =
    messages.filterMap(m => {
      match m {
        | Prop(p) => Some(p)
        | _ => None
      }
    })

  pure def get_votes(messages: Set[Message]): Set[VoteMsg] =
    messages.filterMap(m => {
      match m {
        | Vote(v) => Some(v)
        | _ => None
      }
    })

  pure def get_timeouts(messages: Set[Message]): Set[TimeoutMsg] =
    messages.filterMap(m => {
      match m {
        | Timeout(t) => Some(t)
        | _ => None
      }
    })

  pure def get_timeout_events(events: Set[InternalEvent]): Set[TimeoutData] =
    events.filterMap(e => {
      match e {
        | TimeoutEvent(data) => Some(data)
      }
    })

  pure def displayer(ctx: GlobalContext): Address -> Set[ProposalID] = {
    ctx.extensions.logging.committed_proposals
      .transformValues(s => s.map(p => p.proposal_id))
  }
}
