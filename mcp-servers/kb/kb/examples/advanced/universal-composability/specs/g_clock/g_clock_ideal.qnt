module g_clock_ideal {

  import basicSpells.* from "../../spells/basicSpells"
  import choreo(processes = NODES) as choreo from "../../choreo"

  pure val GLOCK : Node = 1
  pure val ENV   : Node = 2
  pure val SIM   : Node = 3
  pure val NODES  = Set(GLOCK,ENV,SIM)

  // - Disambiguate messages with salt(e.g., counter) to allow repeations (only when strictly nec.)
  // - Responsive/non-responsive simulator (idea: add some combinators for SIM)
// https://quint-lang.org/docs/model-checkers
  pure val SIDs = 1.to(5) // session ids
  pure val honestParties = Set(1,2,3)
  pure val corruptedParties = Set(4)
  pure val allParties = honestParties.union(corruptedParties)

  // Auxiliary types
  type Role = GLOCK_ROLE | SIM_ROLE | ENV_ROLE 

  type Party = int
  type SID = int
  type Time = int
  type PartySID = {party:Party, sid:SID}

  type History = {
    msg_log: Set[({idx:int, msg: Message, time: Time, Reg: Set[PartySID], ok: Set[PartySID]})],
  }  

  // Mandatory types for the Choreo
  type Node = int
  type Message =

    | RegisterRequest(PartySID) 
    | RegisterResponse(PartySID)

    | TimeRequest(PartySID) 
    | TimeResponse({party:PartySID, time:Time})

    | OkayRequest(PartySID)
    | SIMOkayHold(PartySID)
    | SIMOkayRelease(PartySID)
    | OkayResponse(PartySID)

    | EnvGiveControl
    | SIMGiveControl

   
  type StateFields = {
    // functionality variables
    TIME: int,
    Reg: Set[PartySID],
    ok:  Set[PartySID],
    role: Role,

    // simulator variables
    sim_handles : Set[(int, Message)], // for SIM to store hold requests
    sim_ctr : int,
  }

  type CustomEffects = ExcludeMsg({node:Node, msg:Message}) | Log(Message)
  type Event = ()
  type Extensions = History

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


  def choreo_s = {
    choreo::s
  }

  def choreo_display = {
    choreo::display
  }  

  def choreo_CustomEffect = {
    choreo::CustomEffect
  }

  def choreo_Send = {
    choreo::Send
  }  

  action choreo_process_transitions = {
    choreo::process_transitions
  }




  pure def get_register_request_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | RegisterRequest(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_register_response_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | RegisterResponse(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_time_request_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | TimeRequest(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_time_response_messages(messages: Set[Message]): Set[{party:PartySID, time:Time}] = {
    messages.filterMap(m => {
      match m {
        | TimeResponse(t) => Some(t)
        | _ => None
      }
    })
  }

  pure def get_okay_request_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | OkayRequest(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_okay_hold_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | SIMOkayHold(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_okay_release_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | SIMOkayRelease(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_okay_response_messages(messages: Set[Message]): Set[PartySID] = {
    messages.filterMap(m => {
      match m {
        | OkayResponse(p) => Some(p)
        | _ => None
      }
    })
  }
  /* End of boilerplate */
        
  // --- Party transitions ----------------------------------------------
  pure def register(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == GLOCK_ROLE){
      ctx.messages.get_register_request_messages().map(p => {
          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: RegisterRequest(p)}) ),
              choreo::CustomEffect(Log(RegisterRequest(p))),
              choreo::Send(({to: ENV, message: RegisterResponse(p)})),
            ),
            post_state: { ...ctx.state, 
              Reg: ctx.state.Reg.union(Set(p)),
            }, 
          })
      }).flatten()
    }else{
      Set()
    }
  }  

  pure def time(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == GLOCK_ROLE){
      ctx.messages.get_time_request_messages().map(p => {
          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: TimeRequest(p)})),
              choreo::CustomEffect(Log(TimeRequest(p))),
              choreo::Send(({ to: ENV, message: TimeResponse({party:p, time:ctx.state.TIME}) })),
            ),
            post_state: ctx.state, 
          })
      }).flatten()
    }else{
      Set()
    }
  }  

  pure def okay(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == GLOCK_ROLE){
      ctx.messages.get_okay_request_messages().map(p => {
        if(ctx.state.Reg.contains(p)){

          val flag = ctx.state.Reg.forall(rp => ctx.state.ok.contains(rp) or rp == p) 
          val new_time = if (flag) ctx.state.TIME + 1 else ctx.state.TIME
          val new_ok = if (flag) Set() else ctx.state.ok.setAdd(p)

          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: OkayRequest(p)})),
              choreo::CustomEffect(Log(OkayRequest(p))),
              choreo::Send(({ to: SIM, message: SIMOkayHold(p) })),
            ),
            post_state: { ...ctx.state, 
              ok: new_ok, 
              TIME: new_time, 
            }, 
          })
        }else{
          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: OkayRequest(p)})),
              choreo::CustomEffect(Log(OkayRequest(p))),
              choreo::Send(({ to: ENV, message: EnvGiveControl })),
            ),
            post_state: ctx.state, 
          })
        }
      }).flatten()
    }else{
      Set()
    }
  }

  pure def glock_released(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == GLOCK_ROLE){
      ctx.messages.get_sim_okay_release_messages().map(p => {
          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg({node:ctx.state.process_id, msg: SIMOkayRelease(p)})),
              choreo::Send(({ to: ENV, message: OkayResponse(p) })),
            ),
            post_state: ctx.state, 
          })
      }).flatten()
    }else{
      Set()
    }
  }    

  // storing the hold requests
  pure def sim_store_hold_reqs(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == SIM_ROLE and ctx.messages.get_sim_okay_hold_messages().size() > 0){
      val juice = ctx.messages.get_sim_okay_hold_messages().find(x => true).unwrap()
      val hold_msg = SIMOkayRelease(juice)
         Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMOkayHold(juice) })),
              choreo::Send(({ to: SIM, message: SIMGiveControl })),
            ),
            post_state: { ...ctx.state, 
              sim_handles: ctx.state.sim_handles.union(Set((ctx.state.sim_ctr + 1, hold_msg))),
              sim_ctr: ctx.state.sim_ctr + 1,
            }, 
          })      
    }else{
      Set()
    }
  }

  // either:
  // 1. release one of the stored hold requests
  // 2. give control back to ENV
  pure def sim_process_hold_reqs(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == SIM_ROLE and ctx.state.sim_handles.size() > 0 and ctx.messages.contains(SIMGiveControl)){
      val release_trans = ctx.state.sim_handles.map(release_request =>
      
        Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMGiveControl })),
              choreo::Send(({ to: GLOCK, message: release_request._2  })), 
            ),
            post_state: { ...ctx.state, 
              sim_handles: ctx.state.sim_handles.exclude(Set( release_request) ),
            }, 
          })      
      ).flatten()

      release_trans.union(
        Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMGiveControl })),
              choreo::Send(({ to: ENV, message: EnvGiveControl })),
            ),
            post_state: ctx.state, 
          })      
      )
      
    }else{
      Set()
    }
  }

  pure def main_listener(ctx: LocalContext): Set[Transition] =
    Set(
      register(ctx),
      time(ctx),
      okay(ctx),
      sim_store_hold_reqs(ctx),
      sim_process_hold_reqs(ctx),
      glock_released(ctx)
    ).flatten()

  pure def apply_custom_effect(env: GlobalContext, effect: CustomEffects): GlobalContext = {
    match effect {
      | ExcludeMsg(p) => {... env, messages: env.messages.setBy(p.node, (old => old.exclude(Set(p.msg))))}
      | Log(msg) => {
          {...env, extensions: {...env.extensions, msg_log: env.extensions.msg_log.setAdd(
            { idx:env.extensions.msg_log.size(),
              msg:msg,
              time: env.system.get(GLOCK).TIME,
              Reg: env.system.get(GLOCK).Reg,
              ok: env.system.get(GLOCK).ok,})}}
      }
    }
  }

  action step = any {
    choreo::step(
    (ctx => main_listener(ctx)),
    apply_custom_effect),
    //interact
  }

  action stutter = all {
    choreo::s' = choreo::s
  }


  pure def initialize(n: Node): LocalState = {
    {
      process_id: n,
      TIME: 0,
      ok:  Set(),
      Reg: Set({party:1,sid:1}),

      role: if (n == GLOCK) GLOCK_ROLE else if (n == SIM) SIM_ROLE else ENV_ROLE,

      sim_handles : Set(),
      sim_ctr : 0,

    }
  }

  pure val initial_history = {
    msg_log: Set(),
  }  

  action init = 
    choreo::init({
      system: NODES.mapBy(n => initialize(n)),
      messages: NODES.mapBy(n => if (n == ENV)  
         Set()
       else Set()),
    events: NODES.mapBy(n => Set()),
    extensions: initial_history
  })  
  

  // action interact : bool = all {

  //   choreo::s.messages.get(ENV).size() > 0,

  //   nondet envmsg = oneOf(choreo::s.messages.get(ENV))
  //   nondet node = oneOf(NODES)
  //   nondet sid = oneOf(SIDs)
  //   nondet req = 1.to(3).oneOf()

  //   val msg = if (req == 1) {
  //     RegisterRequest({party:node, sid:sid})
  //   } else if (req == 2) {
  //     OkayRequest({party:node, sid:sid})
  //   } else /* req == 3 */ {
  //     TimeRequest({party:node, sid:sid})
  //   }

  //   val req_transition = {
  //         effects: Set(
  //           choreo::CustomEffect(Log(envmsg)),
  //           choreo::CustomEffect(ExcludeMsg( {node:ENV, msg: envmsg }) ),
  //           choreo::Send(({ to: GLOCK, message: msg })),
  //         ),
  //         post_state: choreo::s.system.get(ENV), 
  //       }

  //   val sim_transition = {
  //         effects: Set(
  //           choreo::CustomEffect(Log(envmsg)),
  //           choreo::CustomEffect(ExcludeMsg( {node:ENV, msg: envmsg }) ),
  //           choreo::Send(({ to: SIM, message: SIMGiveControl })),
  //         ),
  //         post_state: choreo::s.system.get(ENV), 
  //       }        

  //   choreo::process_transitions(ENV, Set(req_transition), apply_custom_effect)
  // }

  // --- Properties -----------------------------------------------------

// Property: system is well-defiend
val OneMsgInTheSystem = and {
    choreo::s.messages.get(SIM).size() <= 1,
    choreo::s.messages.get(ENV).size() <= 1,
    choreo::s.messages.get(GLOCK).size() <= 1
}
    

// Property: Liveness 
val LogGrows = 
    choreo::s.extensions.msg_log.size() < 5

// must fail
val TimeAdvances = choreo::s.system.get(GLOCK).TIME < 2
   
// must fail
val HandlesLiveness = 
    choreo::s.system.get(SIM).sim_handles.size() < 2
  
// Property 1 (Time Agreement): If two parties query the time and no OK requests have been sent in the middle then G-clock responds with the same time.
val TimeAgreement = choreo::s.extensions.msg_log.forall(r1 =>
    match r1.msg {
      | TimeResponse(t1) =>
          choreo::s.extensions.msg_log.forall(r2 =>
            match r2.msg {
              | TimeResponse(t2) =>
                  if (r2.idx > r1.idx) {
                    // Check that no OK requests in between
                    val no_okay_in_between = choreo::s.extensions.msg_log.forall(rm =>
                      if (rm.idx > r1.idx and rm.idx < r2.idx) {
                        match rm.msg {
                          | OkayRequest(_) => false
                          | _ => true
                        }
                      } else {
                        true
                      }
                    )
                    if (no_okay_in_between) {
                      t1.time == t2.time
                    } else {
                      true
                    }
                  } else {
                    true
                  }
              | _ => true
            }
          )
      | _ => true
    }
  )



// Property 2 (Time Liveness):  If all registered parties are ready, then time advances.
// this is non-trivial since we have to track who was registered and corrupted at all times
val TimeLiveness = choreo::s.extensions.msg_log.forall(r1 =>
   choreo::s.extensions.msg_log.forall(r2 =>
            if (r2.idx == r1.idx + 1) {
              match r2.msg {
                | OkayRequest(p) =>
                      // check if all registered parties were ready at r1
                      val all_ready = r1.Reg.forall(rp => r1.ok.contains(rp) or rp == p)
                    
                      if (r2.Reg.contains(p) and all_ready) {
                        r2.time == r1.time + 1
                      } else {
                        r2.time == r1.time
                      }
                    
                | _ => r2.time == r1.time
              }
            } else {
              true
            }
          )
  )



// Property 3 (Time Soundness): If time advanced then all currently registered parties were ready.
// this is boring since we have a full control of when to advance time
val TimeSoundness = choreo::s.extensions.msg_log.forall(r1 =>
   choreo::s.extensions.msg_log.forall(r2 =>
            if (r2.idx == r1.idx + 1 and r2.time > r1.time) {
              match r2.msg {
                | OkayRequest(p) =>
                      // time advanced, check that all registered parties were ready
                      val all_ready = r1.Reg.forall(rp => r1.ok.contains(rp) or rp == p)
                    and {
                      all_ready,
                      r2.time == r1.time + 1,
                      r2.ok == Set(),
                    }
                | _ => false
              }
            } else {
              true
            }
          )
  )
}