module f_sig_ideal {

  import basicSpells.* from "../../spells/basicSpells"
  import choreo(processes = NODES) as choreo from "../../choreo"

  pure val FSig : Node = 1
  pure val ENV  : Node = 2
  pure val SIM  : Node = 3
  pure val NODES = Set(FSig,ENV,SIM)

  // - Disambiguate messages with salt(e.g., counter) to allow repeations (only when strictly nec.)
  // - Responsive/non-responsive simulator (idea: add some combinators for SIM)

  pure val honestParties = Set(1)
  pure val corruptedParties = Set(2)
  pure val allParties = honestParties.union(corruptedParties)
  pure val allVKs  = 1.to(5)
  pure val allSigs = 1.to(5)
  pure val allDocs = Set("doc1","doc2")


  var counter : int

  // Auxiliary types
  type Role = SigIF | SigSim | Env 

  type Party = int
  type PublicKey = int
  type Document = str
  type Signature = int

  type History = {
    msg_log: Set[Message],
  }  

  // Mandatory types for the Choreo
  type VerEntry = {
    vk  : PublicKey, 
    msg : Document, 
    sig : Signature,
    res : bool
  }

  type VKEntry = {
    party : Party,
    vk : PublicKey
  }

  type Node = int
  type Message =

    | GenRequest(Party) // input for FSig
    | GenResponse(VKEntry) // output of FSig
    | SIMGen(Party) // input to SIM
    | SIMReleaseGen(VKEntry) // output of SIM

    | SignRequest({party:Party, msg : Document}) // input for FSig
    | SignResponse({party:Party, ver_entry:VerEntry}) // output of FSig
    | SIMSign({party:Party, msg:Document})  // input to SIM
    | SIMReleaseSign({party:Party,msg:Document,sig:Signature}) // output of SIM

    | VerifyRequest({party:Party, vk:PublicKey, msg:Document, sig:Signature}) // input to FSig
    | VerifyResponse({party:Party, ver_entry:VerEntry}) // output of FSig
    | SIMVerify({party:Party, vk:PublicKey, msg:Document, sig:Signature}) // input to SIM
    | SIMReleaseVerify({party:Party, ver_entry:VerEntry}) // output of SIM


  type StateFields = {
    VK:   Set[VKEntry],
    Ver:  Set[VerEntry],
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

  pure def get_verify_sim_messages(messages: Set[Message]): Set[{party:Party, vk:PublicKey, msg:Document, sig:Signature}] = {
    messages.filterMap(m => {
      match m {
        | SIMVerify(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_gen_messages(messages: Set[Message]): Set[Party] = {
    messages.filterMap(m => {
      match m {
        | SIMGen(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_sign_messages(messages: Set[Message]): Set[{party:Party, msg:Document}] = {
    messages.filterMap(m => {
      match m {
        | SIMSign(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_release_sign_messages(messages: Set[Message]): Set[{party:Party, msg:Document, sig:Signature}] = {
    messages.filterMap(m => {
      match m {
        | SIMReleaseSign(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_release_verify_messages(messages: Set[Message]): Set[{party:Party, ver_entry:VerEntry}] = {
    messages.filterMap(m => {
      match m {
        | SIMReleaseVerify(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_sim_release_gen_messages(messages: Set[Message]): Set[VKEntry] = {
    messages.filterMap(m => {
      match m {
        | SIMReleaseGen(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_gen_request_messages(messages: Set[Message]): Set[Party] = {
    messages.filterMap(m => {
      match m {
        | GenRequest(party) => Some(party)
        | _ => None
      }
    })
  }

  pure def get_sign_request_messages(messages: Set[Message]): Set[{party:Party, msg:Document}] = {
    messages.filterMap(m => {
      match m {
        | SignRequest(p) => Some(p)
        | _ => None
      }
    })
  }

  pure def get_verify_request_messages(messages: Set[Message]): Set[{party:Party, vk:PublicKey, msg:Document, sig:Signature}] = {
    messages.filterMap(m => {
      match m {
        | VerifyRequest(p) => Some(p)
        | _ => None
      }
    })
  }
  /* End of boilerplate */

  // --- Party transitions ----------------------------------------------
  pure def vk_generation_ideal1(ctx: LocalContext) : Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_gen_request_messages().map(party => {
        if (ctx.state.VK.exists(x => x.party == party)){
          val pk = ctx.state.VK.find(x => x.party == party).unwrap().vk

          Set({
            effects: Set(
                choreo::Send( ({ to: ENV, message: GenResponse({party: party, vk: pk}) })),
                choreo::CustomEffect(ExcludeMsg({node:ctx.state.process_id, msg: GenRequest(party)}))
                        ),
            post_state: { ...ctx.state}
               })
      // VK does not exist, send msg to SIM (no state to preserve)
      }else{
        Set({
          effects: Set(
            choreo::Send(({ to: SIM, message: SIMGen(party)})),
            choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: GenRequest(party)}) )),
          post_state: { ...ctx.state }
        })}
      }).flatten()
  }


  pure def vk_generation_sim(ctx: LocalContext) : Set[Transition] = {
    if (ctx.state.role == SigSim) { // only SIM can process this
      ctx.messages.get_sim_gen_messages().map(p => {
        allVKs.map(vk =>
          Set({
            effects: Set(
                choreo::Send( ({ to: FSig, message: SIMReleaseGen({party: p, vk:vk}) })),
                choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMGen(p)}))
              ),
            post_state: { ...ctx.state }
          })
        ).flatten()
      }).flatten()
    }else{
      Set()
    }

  }

  pure def vk_generation_ideal2(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_sim_release_gen_messages().map(p => {
        def filter_fun = (p) =>
          or {
            ctx.state.VK.exists (x => x.vk == p),
            ctx.state.Ver.exists(x => x.vk == p)
          }

        val san_vk_option = if(not (filter_fun(p.vk))){
          Some(p.vk)
        }else{
          allVKs.find(p => not(filter_fun(p)))
        }

        if(san_vk_option != None){

          val san_vk = san_vk_option.unwrap()

          Set({
            effects: Set(
                choreo::Send( ({ to: ENV, message: GenResponse({party:p.party, vk:san_vk}) } ) ),
                choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMReleaseGen(p)}) )
            ),
            post_state: { ...ctx.state, VK: ctx.state.VK.union(Set({party:p.party, vk:san_vk})),}
          })
        }else{ // no fresh VKs are left
          Set()
          // TODO: can we do an exception here?
        }
      }).flatten()
    }


  pure def msg_sign_ideal1(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_sign_request_messages().map(p => {
        if(not (ctx.state.VK.exists(x => x.party == p.party))){ // party does not have vk
          Set()
        }else{
          Set({
            effects: Set(
                choreo::Send( ({ to: SIM, message: SIMSign({party:p.party, msg:p.msg})})),
                choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SignRequest(p)}) ),
                choreo::CustomEffect(Log(SignRequest(p)) ),
            ),
            post_state: { ...ctx.state }
          })
        }
      }).flatten()
  }

  pure def msg_sign_sim(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigSim){
      Set()
    }else
      ctx.messages.get_sim_sign_messages().map(p => {
        allSigs.map(sig =>
          Set({
            effects: Set(
                choreo::Send(({ to: FSig, message: SIMReleaseSign({party:p.party, msg:p.msg, sig:sig})})),
                choreo::CustomEffect(ExcludeMsg({node:ctx.state.process_id, msg: SIMSign(p)}))
            ),
            post_state: { ...ctx.state }
          })
        ).flatten()
      }).flatten()
  }

  pure def msg_sign_ideal2(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_sim_release_sign_messages().map(p => {
        val vk_opt = ctx.state.VK.find(x => x.party == p.party)

        if (vk_opt == None){ // vk doesn't exist for a party
          Set()
        }else{
          val vk = vk_opt.unwrap().vk

          def filter_fun = (x) =>
            ctx.state.Ver.exists(y => y.vk == vk and
                                      y.msg == p.msg and
                                      y.sig == x)


          val san_sig_opt = if (not(filter_fun(p.sig))){
            Some(p.sig)
          }else{
            allSigs.find(x => not(filter_fun(x)))
          }

          if (san_sig_opt != None){
            val san_sig = san_sig_opt.unwrap()

            Set({
              effects: Set(
                  choreo::Send( ({ to: ENV, message: SignResponse({party:p.party, ver_entry:{vk: vk, msg:p. msg, sig: san_sig, res: true}}) } ) ),
                  choreo::CustomEffect(ExcludeMsg({node:ctx.state.process_id, msg: SIMReleaseSign(p)}) )
              ),
              post_state: { ...ctx.state, Ver: ctx.state.Ver.union(Set({vk:vk, msg:p.msg, sig:san_sig, res:true})),}
            })
          }else{ // out of signatures
            Set()
          }
        }
      }).flatten()
  }


  pure def msg_verify_ideal1(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_verify_request_messages().map(p => {
        // buggy check for original version of f_sig, falsifies VerConsistent
         // if((ctx.state.Ver.exists(x => x.vk == vk and x.msg == msg and x.sig == sig))){
          //  Set() // todo: send response
          //}else{
            Set({
              effects: Set(
                  choreo::Send( ({ to: SIM, message: SIMVerify({party:p.party, vk:p.vk, msg:p.msg, sig:p.sig})})),
                  choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: VerifyRequest(p)}))
              ),
              post_state: { ...ctx.state }
            })
          //}
      }).flatten()
  }

  pure def msg_verify_sim(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigSim){
      Set()
    }else
      ctx.messages.get_verify_sim_messages().map(p => {
        Set(true, false).map(res =>
          Set({
            effects: Set(
                choreo::Send( ({ to: FSig,
                            message: SIMReleaseVerify({party:p.party,
                                                        ver_entry: {vk:p.vk,msg:p.msg,sig:p.sig,res:res}})})),
                choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMVerify(p)}))
            ),
            post_state: { ...ctx.state }
          })
        ).flatten()
      }).flatten()
  }

  pure def msg_verify_ideal2(ctx: LocalContext): Set[Transition] = {
    if(ctx.state.role != SigIF){
      Set()
    }else
      ctx.messages.get_sim_release_verify_messages().map(p => {
        val ver = p.ver_entry

        val san_res = if(ctx.state.VK.exists(x => x.party.in(honestParties) and x.vk == ver.vk)){
          false
        }else{
          ver.res
        }

        if(ctx.state.Ver.exists(x => all {
            x.vk == ver.vk,
            x.msg == ver.msg,
            x.sig == ver.sig
            })){
          Set() // TODO: send response?
        }else{
          Set({
            effects: Set(
                choreo::Send( ({ to: ENV, message: VerifyResponse({party:p.party, ver_entry:{vk:ver.vk,msg:ver.msg,sig:ver.sig,res:san_res}} ) } ) ),
                choreo::CustomEffect(ExcludeMsg( {node:ctx.state.process_id, msg: SIMReleaseVerify(p)}) )
            ),
            post_state: { ...ctx.state, Ver: ctx.state.Ver.union(Set({vk:ver.vk, msg:ver.msg, sig:ver.sig, res:san_res})),}
          })
        }
      }).flatten()
  }


  // environment throws in verification requests
  pure def env_verify_msgs(ctx:LocalContext) : Set[Transition] = {
    if (ctx.state.role != Env ) {
      Set()
    }else{ // nondeterministic verification messages
      allParties.map(party => {
        allVKs.map(vk => {
          allDocs.map(msg => {
            allSigs.map(sig => {
            Set(
              { 
                effects: Set (
                  choreo::Send( ({ to: FSig, message: VerifyRequest({party:party,vk:vk,msg:msg,sig:sig} ) } ) )
                ), 
                post_state: { ...ctx.state }
              }
            )
            }).flatten()
          }).flatten()
        }).flatten()
      }).flatten()
    }
  }

  // boilerplate from here
  def apply_custom_effect(env: GlobalContext, effect: CustomEffects): GlobalContext = {
    match effect {
      | ExcludeMsg(p) => {... env, messages: env.messages.setBy(p.node, (old => old.exclude(Set(p.msg)))) }
      | Log(msg) => {
          {...env, extensions: {...env.extensions, msg_log: env.extensions.msg_log.setAdd(msg)}}
        }
    }
  }

  pure def main_listener(ctx: LocalContext): Set[Transition] =
    Set(
      vk_generation_ideal1(ctx),
      vk_generation_ideal2(ctx),
      vk_generation_sim(ctx) 
    ).flatten()

  action gen_step1 = choreo::step(
    (ctx => vk_generation_ideal1(ctx)),
    apply_custom_effect
  )
  action gen_step2 = choreo::step(
    (ctx => vk_generation_ideal2(ctx)),
    apply_custom_effect
  )
  action gen_step3 = choreo::step(
    (ctx => vk_generation_sim(ctx)),
    apply_custom_effect
  )
  action sign_step1 = choreo::step(
    (ctx => msg_sign_ideal1(ctx)),
    apply_custom_effect
  )
  action sign_step2 = choreo::step(
    (ctx => msg_sign_ideal2(ctx)),
    apply_custom_effect
  )
  action sign_step3 = choreo::step(
    (ctx => msg_sign_sim(ctx)),
    apply_custom_effect
  )
  action verify_step1 = choreo::step(
    (ctx => msg_verify_ideal1(ctx)),
    apply_custom_effect
  )
  action verify_step2 = choreo::step(
    (ctx => msg_verify_ideal2(ctx)),
    apply_custom_effect
  )
  action verify_step3 = choreo::step(
    (ctx => msg_verify_sim(ctx)),
    apply_custom_effect
  )

  action env_step1 = choreo::step(
    (ctx => env_verify_msgs(ctx)),
    apply_custom_effect
  )
    

  action step = any {
    all { gen_step1, counter' = counter,},
    all { gen_step2, counter' = counter,},
    all { gen_step3, counter' = counter,},

    all { sign_step1, counter' = counter,},
    all { sign_step2, counter' = counter,},
    all { sign_step3, counter' = counter,},

    all { verify_step1, counter' = counter,},
    all { verify_step2, counter' = counter,},
    all { verify_step3, counter' = counter,},

    all { counter < 2,
          env_step1,
          counter' = counter + 1 }
  }

  pure def initialize(n: Node): LocalState = {
    {
      process_id: n,
      VK: Set(),
      Ver: Set(),
      role: if (n == FSig) SigIF else if (n == SIM) SigSim else Env
    }
  }

  pure val initial_history = {
    msg_log: Set(),
  }  

  action init = all {
    choreo::init({
      system: NODES.mapBy(n => initialize(n)),
      messages: NODES.mapBy(n => if (n == 1)  
         Set( GenRequest(1),
              GenRequest(2),
              SignRequest({party:2,msg:"doc1"})
          ) 
       else Set()),
    events: NODES.mapBy(n => Set()),
    extensions: initial_history
  })  ,
  counter' = 0

  }

  // --- Properties ----------------------------------------------------------- 
  // tlc: https://learntla.com/core/action-properties.html

  // Proeprty(MUST FAIL): ensures that system is live
  val GenLiveness  = choreo::s.system.get(FSig).VK.size() <= 1
  val SignLiveness = choreo::s.system.get(FSig).Ver.size() <= 1
  // Property(MUST FAIL): If Ver containts some vk entry  then VK table must  contain respective entry
  val VKVerConsistentDishonest = choreo::s.system.get(FSig).Ver.forall(
    entry => choreo::s.system.get(FSig).VK.exists(p => p.vk == entry.vk))  
  // Propery(MUST FAIL): If Ver contains entry then environment received a respective response
  val VerifiesIfSignedDishonest = choreo::s.system.get(FSig).Ver.forall(entry => {
      (entry.res).implies({
        val vkentry = choreo::s.system.get(FSig).VK.find((x) => x.vk == entry.vk)
        (vkentry != None).implies({
          val party = vkentry.unwrap().party
          party.in(corruptedParties).implies(
            choreo::s.messages.get(ENV).exists(m => {
              m == SignResponse({party:party, ver_entry: entry})
            })
          )
        })
      })
  })   
  // Property: entries don't disappear from Ver for honest
  temporal VerOnlyGrows = always (
    // TODO: bug report (wrong compilation of "always" to both tlc and apalache)
    choreo::s.system.get(FSig).Ver.forall(x => {
      x.in(next(choreo::s.system.get(FSig).Ver))
    })
  )
  // Property: nothing disappears from VK
  temporal VKOnlyGrows = always (
    // TODO: bug report (wrong compilation of "always" to both tlc and apalache)
    choreo::s.system.get(FSig).VK.forall(x => {
      x.in(next(choreo::s.system.get(FSig).VK))
    })
  )
  // Property: party has at most one verification key
  val OneVKperUser = allParties.forall(p => choreo::s.system.get(FSig).VK.filter(x => x.party == p).size() <= 1)
  // Property: verification keys are unique 
  val VKUnique = allVKs.forall(p => choreo::s.system.get(FSig).VK.filter(x => x.vk == p).size() <= 1)
  // Property: Ver is consistent
  val VerConsistent = choreo::s.system.get(FSig).Ver.forall(entry => {
     not ({...entry, res : not(entry.res)}.in(choreo::s.system.get(FSig).Ver))
  })
  // Propery: If Ver contains entry then environment received a respective response
  val VerifiesIfSignedHonest = choreo::s.system.get(FSig).Ver.forall(entry => {
      (entry.res).implies({
        val vkentry = choreo::s.system.get(FSig).VK.find((x) => x.vk == entry.vk)
        (vkentry != None).implies({
          val party = vkentry.unwrap().party
          party.in(honestParties).implies(
            choreo::s.messages.get(ENV).exists(m => {
              m == SignResponse({party:party, ver_entry: entry})
            })
          )
        })
      })
  })   
  // Property: if ENV received GenResponse then the key is in the set of verification keys
  val GenResponseValid = choreo::s.messages.get(ENV).forall(m => match m {
    | GenResponse(p) => choreo::s.system.get(FSig).VK.exists(x => x == p)
    | _ => true
  })  
  // Property: if SignResponse is received by ENV then Ver contains entry
  val SignResponseValid = choreo::s.messages.get(ENV).forall(m => match m {
    | SignResponse(p) => choreo::s.system.get(FSig).Ver.exists(x => x == p.ver_entry)
    | _ => true
  })
  // Property: if VerifyResponse is received then Ver contains the respective entry
  val VerifyResponseValid = choreo::s.messages.get(ENV).forall(m => match m {
    | VerifyResponse(p) => choreo::s.system.get(FSig).Ver.exists(x => x == p.ver_entry)
    | _ => true
  })
  // Property: Correctness -- if all actions are weakly fair then GenResponse is eventually received
  temporal GenCorrectness = 
    gen_step1.weakFair(Set(choreo::s)).implies(
      gen_step2.weakFair(Set(choreo::s)).implies(
        gen_step3.weakFair(Set(choreo::s)).implies(
      choreo::s.messages.get(FSig).exists(m => match m {
        | GenRequest(p) => true
        | _ => false
      }
      ) implies (eventually (choreo::s.messages.get(ENV).exists(m => 
        match m {
          | GenResponse(p) => true
          | _ => false
        })))))
      )
    // Property: conjunction of all val (non temporal) properties (might be slow)
    val AllValProps = all {
      OneVKperUser,
      VKUnique,
      VerConsistent,
      VerifiesIfSignedHonest,
      GenResponseValid,
      SignResponseValid,
      VerifyResponseValid,
    }
}
