module f_nizk_ideal {

  import basicSpells.* from "../../spells/basicSpells"
  import choreo(processes = NODES) as choreo from "../../choreo"

  pure val FNIZK : Node = 1
  pure val ENV   : Node = 2
  pure val SIM   : Node = 3
  pure val NODES  = Set(FNIZK,ENV,SIM)

  // - Disambiguate messages with salt(e.g., counter) to allow repeations (only when strictly nec.)
  // - Responsive/non-responsive simulator (idea: add some combinators for SIM)

  pure val proverParties = Set(1)
  pure val verifierParties = Set()
  pure val allParties = proverParties.union(verifierParties)
  pure val allStatements  = 1.to(5)
  pure val allWitnesses = 1.to(5)
  pure val allProofs = 1.to(5)




  // Auxiliary types
  type Role = FNIZK_ROLE | SIM_ROLE | ENV_ROLE 

  type Party = int
  type Witness = int
  type Statement = int
  type Proof = int

  type History = {
    msg_log: Set[Message],
  }  

  // Mandatory types for the Choreo


  type Node = int
  type Message =

    | ProveRequest({party:Party, stm : Statement, witness: Witness}) // input for FNIZK
    | SIMProve({party:Party, stm : Statement, witness: Witness}) // input to SIM
    | SIMReleaseProve({party:Party, stm: Statement, witness : Witness, proof : Proof}) // output of SIM    
    | ProveResponse(Option[{stm : Statement, witness : Witness, proof : Proof}]) // output of FNIZK

    | VerifyRequest({party:Party, stm: Statement, proof: Proof}) // input for FNIZK
    | SIMVerify({party:Party, stm : Statement, proof: Proof}) // input to SIM
    | SIMReleaseVerify({party:Party, stm: Statement, proof : Proof, witness : Witness}) // output of SIM  
    | VerifyResponse({stm: Statement, proof : Proof, result : bool}) // output of FNIZK

   

  type StateFields = {
    Ver:  Set[(Statement, Proof, bool)],
    Rel:  Set[(Statement, Witness)],
    role: Role,
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


  pure def get_prove_request_messages(messages: Set[Message]): Set[{party:Party, stm : Statement, witness: Witness}] = {
    messages.filterMap(m => {
      match m {
        | ProveRequest(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_verify_request_messages(messages: Set[Message]): Set[{party:Party, stm: Statement, proof: Proof}] = {
    messages.filterMap(m => {
      match m {
        | VerifyRequest(p) => Some(p)
        | _ => None
      }
    })
  }  

  pure def get_verify_sim_request_messages(messages: Set[Message]): Set[{party:Party, stm: Statement, proof: Proof}] = {
    messages.filterMap(m => {
      match m {
        | SIMVerify(p) => Some(p)
        | _ => None
      }
    })
  }    

  pure def get_verify_release_request_messages(messages: Set[Message]): Set[{party:Party, stm: Statement, proof : Proof, witness : Witness}] = {
    messages.filterMap(m => {
      match m {
        | SIMReleaseVerify(p) => Some(p)
        | _ => None
      }
    })
  }   

  pure def get_verify_response_messages(messages: Set[Message]): Set[{stm: Statement, proof : Proof, result : bool}] = {
    messages.filterMap(m => {
      match m {
        | VerifyResponse(p) => Some(p)
        | _ => None
      }
    })
  }      

  pure def get_prove_sim_request_messages(messages: Set[Message]): Set[{party:Party, stm : Statement, witness: Witness}] = {
    messages.filterMap(m => {
      match m {
        | SIMProve(p) => Some(p)
        | _ => None
      }
    })
  }  

  pure def get_prove_sim_release_request_messages(messages: Set[Message]): Set[{party:Party, stm: Statement, witness : Witness, proof : Proof}] = {
    messages.filterMap(m => {
      match m {
        | SIMReleaseProve(p) => Some(p)
        | _ => None
      }
    })
  }    

  pure def get_prove_response_messages(messages: Set[Message]): Set[Option[{stm : Statement, witness : Witness, proof : Proof}]] = {
    messages.filterMap(m => {
      match m {
        | ProveResponse(p) => Some(p)
        | _ => None
      }
    })
  }      






  /* End of boilerplate */
        
  // --- Party transitions ----------------------------------------------
  pure def prove_1(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == FNIZK_ROLE){
      ctx.messages.get_prove_request_messages().map(p => {
        val R = ctx.state.Rel
        if(not (R.contains((p.stm, p.witness)))){
          Set({
            effects: Set(
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: ProveRequest(p)}) ),
              choreo::Send(({ to: ENV, message: ProveResponse(None) })),
              ),
              // TODO, add bottom message to indicate failure
            post_state: { ...ctx.state }
          })
        }else{
          Set({
            effects: Set(
              choreo::Send(({ to: SIM, message: SIMProve(p) })),
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: ProveRequest(p)}) )),
            post_state: { ...ctx.state }
          })
        }
      }).flatten()
    }else{
      Set()
    }
  }

  pure def prove_sim(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == SIM_ROLE){
      ctx.messages.get_prove_sim_request_messages().map(p => {
        allProofs.map(prf => {
          Set({
            effects: Set(
              choreo::Send(({ to: FNIZK, message: SIMReleaseProve({party:p.party, stm: p.stm, witness: p.witness, proof: prf}) })),
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMProve(p)}) )),
            post_state: { ...ctx.state }
          })
        }).flatten()
      }).flatten()
    }else{
      Set()
    }
  }      

  pure def prove_2(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == FNIZK_ROLE){
      ctx.messages.get_prove_sim_release_request_messages().map(p => {
      val san_pk =  if(ctx.state.Ver.contains((p.stm, p.proof, false))){
          allProofs.find(prf => not (ctx.state.Ver.contains((p.stm, prf, false)))).unwrap()
        }else{
          p.proof
        }

      Set({
        
        effects: Set(
          choreo::Send(({ to: ENV, message: ProveResponse(Some({stm : p.stm, witness: p.witness, proof: san_pk})) })),
          choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMReleaseProve(p)}) )),
        post_state: { ...ctx.state, Ver: ctx.state.Ver.union(Set((p.stm, san_pk, true))) }
      })
       }).flatten()
    }else{
      Set()
    }
  }
  
      
  pure def verify_1(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == FNIZK_ROLE){
      ctx.messages.get_verify_request_messages().map(p => {
        Set({
          effects: Set(
            choreo::Send(({ to: SIM, message: SIMVerify(p) })),
            choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: VerifyRequest(p)}) )),
          post_state: ctx.state })
      }).flatten()
    }else{
      Set()
    }
  }

  pure def verify_sim(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == SIM_ROLE){
      ctx.messages.get_verify_sim_request_messages().map(p => {
        //Set()
        allWitnesses.map(wit => {
          Set({
            effects: Set(
              choreo::Send(({ to: FNIZK, message: SIMReleaseVerify({party:p.party, stm: p.stm, proof : p.proof, witness : wit}) })),
              choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMVerify(p)}) )),
            post_state: ctx.state })
        }).flatten()  
      }).flatten()
    }else{
      Set()
    }
  }

  pure def verify_2(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == FNIZK_ROLE){
      ctx.messages.get_verify_release_request_messages().map(p => {
        val ver_entry = ctx.state.Ver.find(e => e._1 == p.stm and e._2 == p.proof)

        val result = if(ver_entry != None){
          ver_entry.unwrap()._3
        }else{
          ctx.state.Rel.contains((p.stm, p.witness))
        }

        Set({
          effects: Set(
            choreo::Send(({ to: ENV, message: VerifyResponse({stm: p.stm, proof: p.proof, result: result}) })),
            choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMReleaseVerify(p)}) )),
          post_state: { ...ctx.state, Ver: ctx.state.Ver.union(Set((p.stm, p.proof,result))) }
        })
      }).flatten()
    }else{
      Set()
    }
  }

  pure def allVerifyRequests : Set[Message] = {
    allParties.map(party =>
      allStatements.map(stm =>
        allProofs.map(proof =>
          VerifyRequest({party:party, stm : stm, proof: proof})
    ))).flatten().flatten()
  }  

  pure def env_verify(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == ENV_ROLE){
      allParties.map(party =>
        allStatements.map(stm =>
          allProofs.map(proof =>
            Set({
              effects: Set(
                choreo::Send(({ to: FNIZK, message: VerifyRequest({party:party, stm: stm, proof: proof}) })),
              ),
              post_state: ctx.state
            })
      ))).flatten().flatten().flatten()
    }else{
      Set()
    }
  }

  pure def allProveRequests : Set[Message] = {
    allParties.map(party =>
      allStatements.map(stm =>
        allWitnesses.map(wit =>
          ProveRequest({party:party, stm : stm, witness: wit})
    ))).flatten().flatten()
  }



  pure def env_prove(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role == ENV_ROLE){
      allProveRequests.map(msg =>
            Set({
              effects: Set(
                choreo::Send(({ to: FNIZK, message: msg })),
              ),
              post_state: ctx.state
            })
      ).flatten()
    }else{
      Set()
    }
  }  

  pure def main_listener(ctx: LocalContext): Set[Transition] =
    Set(
      verify_1(ctx),
      verify_sim(ctx),
      verify_2(ctx),
      prove_1(ctx),
      prove_sim(ctx),
      prove_2(ctx), 
      env_verify(ctx),
      env_prove(ctx),
    ).flatten()

 def apply_custom_effect(env: GlobalContext, effect: CustomEffects): GlobalContext = {
    match effect {
      | ExcludeMsg(p) => {... env, messages: env.messages.setBy(p.node, (old => old.exclude(Set(p.msg)))) }
      | Log(msg) => {
          {...env, extensions: {...env.extensions, msg_log: env.extensions.msg_log.setAdd(msg)}}
        }
    }
  }

  action step = choreo::step(
    (ctx => main_listener(ctx)),
    apply_custom_effect
  )

  pure def initialize(n: Node): LocalState = {
    {
      process_id: n,
      Rel : Set(
        (1,1),
        (1,2),
        (2,2),
        (2,3),
        (3,4)
      ),
      Ver: Set(),
      role: if (n == FNIZK) FNIZK_ROLE else if (n == SIM) SIM_ROLE else ENV_ROLE
    }
  }

  pure val initial_history = {
    msg_log: Set(),
  }  


  action init = all {
    choreo::init({
      system: NODES.mapBy(n => initialize(n)),
      messages: NODES.mapBy(n => if (n == FNIZK)  
         allProveRequests.union(allVerifyRequests)
       else Set()),
    events: NODES.mapBy(n => Set()),
    extensions: initial_history
  })  ,
  }  

  // --- Properties -----------------------------------------------------
  val ProveLiveness_MUST_FAIL = choreo::s.system.get(FNIZK).Ver.size() <= 1

  // if (x,y,b) in Ver, then (x,y,not b) not in Ver
  val NoFlipFlops = choreo::s.system.get(FNIZK).Ver.forall(entry => {
     not ((entry._1, entry._2, not(entry._3)).in(choreo::s.system.get(FNIZK).Ver))
  })

  // Property: if (x,y,true) in Ver, then exists w (x,w) in Rel  
  val VerConsistent = choreo::s.system.get(FNIZK).Ver.forall(entry => {
    (entry._3).implies(
      choreo::s.system.get(FNIZK).Rel.exists(rel_entry => rel_entry._1 == entry._1)
    )
  })

  // Property: if there is a statement stm for which no witness is related, then all verify responses for stm are false
  val VerifySoundness = allStatements.forall(stm => {
    allWitnesses.forall(wit => and { 
      not (choreo::s.system.get(FNIZK).Rel.contains((stm, wit)))
    }).implies(
      choreo::s.messages.get(ENV).get_verify_response_messages().forall(resp => {
        (resp.stm == stm).implies(not (resp.result))
      }))
  })

  // Property: if stm and wit are not in Rel , then all prove responses for (stm, wit) are None
  val ProveSoundness = allStatements.forall(stm => {
    allWitnesses.forall(wit => and { 
      (not (choreo::s.system.get(FNIZK).Rel.contains((stm, wit)))).implies(
        choreo::s.messages.get(ENV).get_prove_response_messages().forall(resp => {
          match resp {
            | None => true
            | Some(p) => (p.stm == stm and p.witness == wit).implies(false)
          }
        })
      )
    })
  })

  // to check liveness
  val Completeness_MUST_FAIL = allStatements.forall(stm => {
    allWitnesses.forall(wit => and { 
      choreo::s.system.get(FNIZK).Rel.contains((stm, wit)).implies(
        choreo::s.messages.get(ENV).get_verify_response_messages().forall(resp => {
          (resp.stm == stm).implies(resp.result)
        }))
    })
  })

  // Property: if stm and with are in Rel then for all prove responses for (stm,wit) and for all 
  // verify responses for stm and proof returned by prove request the result is true
  val Completeness = allStatements.forall(stm => {
    allWitnesses.forall(wit =>  
      choreo::s.system.get(FNIZK).Rel.contains((stm, wit)).implies(
        choreo::s.messages.get(ENV).get_prove_response_messages().forall(resp => {
           (resp != None).implies(
             choreo::s.messages.get(ENV).get_verify_response_messages().forall(vrfy_resp => {
               match resp {
                 | Some(p) => (p.stm == stm and vrfy_resp.stm == stm and p.proof == vrfy_resp.proof).implies(vrfy_resp.result)
                 | None => false
               }
             })
           )
        }))
    )
  })  

  val AllProps = and {
    NoFlipFlops,
    VerConsistent,
    VerifySoundness,
    ProveSoundness,
    Completeness,
  }

}