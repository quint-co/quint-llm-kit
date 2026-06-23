/**
 * Specification of Alpenglow Consensus [1]
 *
 * [1]: https://drive.google.com/file/d/1y_7ddr8oNOknTQYHzXeeMD2ProQ0WjMs/view
 *
 * Josef Widder, Gabriela Moreira
 * Informal Systems, 2025
 */

module alpenglow {
  import basicSpells.* from "./spells/basicSpells"
  import choreo(processes = correct.union(good)) as choreo from "./choreo"

  // -------------------------------------  Constants -------------------------------------------------
  /// Set of correct processes (non Byzantine)
  const correct: Set[ProcessID]
  /// Set of processes that follow the algorithm but might fail in a benign way
  const good: Set[ProcessID]
  /// Set of Byzantine processes
  const byzantine: Set[ProcessID]
  /// Voting power of the processes
  const power: ProcessID -> int
  /// Set of blocks
  const correctBlocks: Set[Block]
  /// Set of Byzantine blocks
  const byzantineBlocks: Set[Block]
  /// Slots for which this model considers votes
  const aliveSlots: Set[Slot]
  /// Hashes for which this model considers votes
  const aliveHashes: Set[Blockhash]
  
  //---------------------------------------------------------------------------------------------------

  type ProcessID = str

  type Slot = int

  type Block = {
    slot: Slot,
    hash: Blockhash,
    parent: Blockhash,
  }

  type BlockReference = { slot: Slot, hash: Blockhash }

  type Blockhash = int

  /// Fields are lists indexed by slot
  type StateFields = {
    pendingBlocks: List[Option[Block]],
    state: List[Set[SlotObject]],
  }

  /// Definition 18 (Votor State)
  type SlotObject =
    | ParentReady(Blockhash)
    | Voted
    | VotedNotar(Blockhash)
    | BlockNotarized(Blockhash)
    | ItsOver
    | BadWindow

  type ConsensusInput =
    | BlockInput(Block)
    | TimeOutInput(Slot)
    | BlockNotarizedInput(BlockReference)
    | ParentReadyInput(BlockReference)
    | SafeToNotarInput(BlockReference)
    | SafeToSkipInput(Slot)

  /// Table 4 (Alpenglow's voting messages)
  type MessageContent =
    | NotarVoteMsg(BlockReference)
    | NotarFallBackVoteMsg(BlockReference)
    | SkipVoteMsg(Slot)
    | SkipFallbackVoteMsg(Slot)
    | FinalVoteMsg(Slot)

  type Certificate =
    | FastFinalizationCertificate(BlockReference)
    | NotarizationCertificate(BlockReference)
    | NotarFallbackCertificate(BlockReference)
    | SkipCertificate(Slot)
    | FinalizationCertificate(Slot)

  type TimeoutEvent = Slot

  type CustomEffects = 
    | ScheduleEventTimeout(TimeoutEvent)
    | ExcludeTimeout(TimeoutEvent)

  type Extensions = {
    // blockchain as seen by message soup
    ch: Slot -> Set[Blockhash],
    // counter for TLC
    counter: int,
  }

  /// Messages on the network carry the sender (the broadcast call in the pseudo code
  /// doesn't carry the sender, so does our encoding of the consensus main loop)
  type Message = {
    sender: ProcessID,
    msg: MessageContent,
  }

  /* Boilerplate */
  type LocalState = choreo::LocalState[ProcessID, StateFields]
  type LocalContext = choreo::LocalContext[ProcessID, StateFields, Message, TimeoutEvent, Extensions]
  type Transition = choreo::Transition[ProcessID, StateFields, Message, TimeoutEvent, CustomEffects]
  type GlobalContext = choreo::GlobalContext[ProcessID, StateFields, Message, TimeoutEvent, Extensions]
  /* End of boilerplate */

  // -----------------------------------------------------------------------------
  // Algorithm implementation from alpenglow.qnt
  // -----------------------------------------------------------------------------

  /// Set of all processes (benevolent and byzantine)
  pure def allProcesses: Set[ProcessID] = correct.union(good).union(byzantine)
  
  /// Set of benevolent processes (correct and good)
  pure def benevolent: Set[ProcessID] = correct.union(good)

  /// Set of all blocks
  pure def allBlocks: Set[Block] = correctBlocks.union(byzantineBlocks)

  /// Byzantine network messages that can be injected  
  pure def byzMessages: Set[Message] = {
    val allMsgs = aliveSlots.fold(Set(), (acc, slot) =>
      aliveHashes.fold(acc, (acc2, hash) =>
        acc2.union(Set(
          NotarVoteMsg({ slot: slot, hash: hash }),
          NotarFallBackVoteMsg({ slot: slot, hash: hash }),
          SkipVoteMsg(slot),
          SkipFallbackVoteMsg(slot),
          FinalVoteMsg(slot)
        ))
      )
    )
    byzantine.fold(Set(), (acc, p) => 
      acc.union(allMsgs.map(msg => { sender: p, msg: msg }))
    )
  }

  pure def addObjects(ls: LocalState, slot: Slot, obj: Set[SlotObject]): LocalState =
    { ...ls, state: ls.state.replaceAt(slot, ls.state[slot].union(obj)) }

  pure def setPendingBlock(ls: LocalState, slot: Slot, b: Option[Block]): LocalState =
    { ...ls, pendingBlocks: ls.pendingBlocks.replaceAt(slot, b) }

  /// Threshold to get a (super)majority
  pure def threshold: int = (allProcesses.size() * 2) / 3 + 1

  // Helper functions for working with power and voting
  pure def totalPower: int = allProcesses.fold(0, (acc, p) => acc + power.get(p))

  pure def powerThreshold: int = (totalPower * 2) / 3 + 1

  pure def powerOfSet(ps: Set[ProcessID]): int = ps.fold(0, (acc, p) => acc + power.get(p))

  pure def surpassesThreshold(ps: Set[ProcessID], percent: int): bool =
    powerOfSet(ps) * 100 >= totalPower * percent

  pure def reference(b: Block): BlockReference = { slot: b.slot, hash: b.hash }

  pure def slotOf(msg: MessageContent): Slot =
    match msg {
      | NotarVoteMsg(m) => m.slot
      | NotarFallBackVoteMsg(m) => m.slot
      | SkipVoteMsg(slot) => slot
      | SkipFallbackVoteMsg(slot) => slot
      | FinalVoteMsg(slot) => slot
    }

  // Definition 5 (ancestor and descendant). An ancestor of a block b is any
  // block that can be reached from b by the parent links, i.e., b, b’s parent,
  // b’s parent’s parent, and so on. If b′ is an ancestor of b, b is a
  // descendant of b′ . Note that b is its own ancestor and descendant.
  pure def isDescendant(a: Block, b: Block): bool = {
    // TODO: this can have better performance if we can make assumptions about slots
    // Filter by minimal slot
    // The slot of the parent will always be smaller then that of the child
    // but its not in increments of 1 like in mysticeti
    pure val bAncestors = (b.slot.to(a.slot)).fold(Set(b.hash), (path, s) =>
      pure val potentialAncestors = allBlocks.filter(block => block.slot == s)
      pure val ancestors = potentialAncestors.filter(ancestor =>
        path.exists(h => ancestor.parent == h)
      )
      path.union(ancestors.map(block => block.hash))
    )

    bAncestors.contains(a.hash)
  }

  /// line 10 of TryNotar. TODO: Is there more to it?
  pure def firstSlotInLeaderWindow(slot: Slot): bool =
    slot % 2 == 0 // TODO implement

  // Definition 13 (certificates)
  // They are defined over a set of messages. Currently we evaluate this over the
  // message soup. But they can be also used over locally received messages if such
  // a semantics is needed.

  /// Table 5: Apenglow's certificate messages.
  pure def isCertified(cert: Certificate, msgs: Set[Message]): bool = {
    val aggregatedVotes = msgs.filter(m => {
      match cert {
        | FastFinalizationCertificate(b) =>
          m.msg == NotarVoteMsg(b)
        | NotarizationCertificate(b) =>
          m.msg == NotarVoteMsg(b)
        | NotarFallbackCertificate(b) =>
          m.msg == NotarVoteMsg(b) or m.msg == NotarFallBackVoteMsg(b)
        | SkipCertificate(s) =>
          m.msg == SkipVoteMsg(s) or m.msg == SkipFallbackVoteMsg(s)
        | FinalizationCertificate(s) =>
          m.msg == FinalVoteMsg(s)
      }
    })

    val threshold = match cert {
      | FastFinalizationCertificate => 80
      | NotarizationCertificate => 60
      | NotarFallbackCertificate => 60
      | SkipCertificate => 60
      | FinalizationCertificate => 60
    }

    aggregatedVotes.map(m => m.sender).surpassesThreshold(threshold)
  }

  pure def notarizedBlocks(msgs: Set[Message]): Set[BlockReference] =
    msgs
      .fold(Set(), (s, x) => match x.msg {
        | NotarVoteMsg(m) => s.union(Set(m))
        | _ => s
      })
      .filter(b => isCertified(NotarizationCertificate(b), msgs))

  pure def slotsSkipCertified(msgs: Set[Message]): Set[Slot] =
    msgs
      .fold(Set(), (s, x) => match x.msg {
        | SkipVoteMsg(m) => s.union(Set(m))
        | _ => s
      })
      .filter(s => isCertified(SkipCertificate(s), msgs))

  // Definition 14 (finalization). We have two ways to finalize a block:
  // Warning: definitions uses "unique" perhaps unclear in case of more faults

  /// If a finalization certificate on slot s is in Pool, the unique notarized block
  /// in slot s is finalized (we call this slow-finalized).
  pure def finalized(slot: Slot, msgs: Set[Message]): Set[Blockhash] =
    allBlocks.map(b => b.reference())
      .filter(b => b.slot == slot)
      .filter(b => {
        isCertified(FinalizationCertificate(b.slot), msgs)
          and isCertified(NotarizationCertificate(b), msgs)
      })
      .map(b => b.hash)

  /// If a fast-finalization certificate on block b is in Pool, the block b is
  /// finalized (fast-finalized).
  pure def fastFinalized(slot: Slot, msgs: Set[Message]): Set[Blockhash] =
    allBlocks.map(b => b.reference())
      .filter(b => b.slot == slot)
      .filter(b => isCertified(FastFinalizationCertificate(b), msgs))
      .map(b => b.hash)

  // Algorithm 2

  pure def windowSlots(slot: Slot): Set[Slot] =
    // TODO: Not sure this makes any sense
    if (slot % 4 == 0)
      Set(slot, slot + 1, slot + 2, slot + 3)
    else if (slot % 4 == 1)
      Set(slot - 1, slot, slot + 1, slot + 2)
    else if (slot % 4 == 2)
      Set(slot - 2, slot - 1, slot, slot + 1)
    else
      Set(slot - 3, slot - 2, slot - 1, slot)

  pure def setTimeouts(ls: LocalState, slot: Slot): Transition =
    { post_state: ls,
      effects: windowSlots(slot).map(i => choreo::CustomEffect(ScheduleEventTimeout(i))) }

  /// Check if a notarization vote can be cast
  pure def tryNotar(ls: LocalState, b: Block): { result: Transition, success: bool } =
    if (ls.state[b.slot].contains(Voted))
      { result: { post_state: ls, effects: Set() }, success: false }
    else
      val firstSlot = firstSlotInLeaderWindow(b.slot)
      if ((firstSlot and ParentReady(b.parent).in(ls.state[b.slot]))
        or (not(firstSlot) and VotedNotar(b.parent).in(ls.state[b.slot - 1])))
        // Warning: parentheses not matching in paper

        // Notarization vote
        val out = Set(choreo::Broadcast(
          { sender: ls.process_id, msg: NotarVoteMsg({ slot:b.slot, hash: b.hash }) }
        ))
        val s2 = addObjects(ls, b.slot, Set(Voted, VotedNotar(b.hash)))
          .setPendingBlock(b.slot, None)

        // Maybe vote finalize as well
        val tf = tryFinal(s2, b.slot, b.hash)

        { result: { post_state: tf.post_state, effects: out.union(tf.effects) }, success: true }
      else
        { result: { post_state: ls, effects: Set() }, success: false }

  pure def tryFinal(ls: LocalState, slot: Slot, hash: Blockhash): Transition =
    if (BlockNotarized(hash).in(ls.state[slot]) and VotedNotar(hash).in(ls.state[slot])
        and not(BadWindow.in(ls.state[slot])))
      // Finalization vote
      {
        effects: Set(choreo::Broadcast({ sender: ls.process_id, msg: FinalVoteMsg(slot) })),
        post_state: addObjects(ls, slot, Set(ItsOver))
      }
    else
      { effects: Set(), post_state: ls }

  pure def trySkipWindow(ls: LocalState, slot: Slot): Transition =
    // Skip unvoted slots
    windowSlots(slot).fold({ effects: Set(), post_state: ls }, (s, k) => {
      if (not(Voted.in(s.post_state.state[k])))
        // Skip vote
        val update = Set(choreo::Broadcast({ sender: ls.process_id, msg: SkipVoteMsg(k) }))
        val s2 = addObjects(s.post_state, k, Set(Voted, BadWindow))
          .setPendingBlock(k, None)

        { effects: s.effects.union(update), post_state: s2 }
      else
        s
    })

  pure def checkPendingBlocks(ls: LocalState): Transition =
    // Iterate with increasing slot
    // (left to right)
    ls.pendingBlocks.foldl({ effects: Set(), post_state: ls }, (res, pendingBlock) =>
      match pendingBlock {
        | Some(b) =>
          val tn = tryNotar(res.post_state, b)
          { effects: res.effects.union(tn.result.effects), post_state: tn.result.post_state }
        | None =>
          res
      }
    )

  pure def parentReadyBlocks(slot: Slot, msgs: Set[Message]): Set[Block] = {
    if (not(firstSlotInLeaderWindow(slot))) Set() else
    allBlocks.filter(b =>
      and {
        b.slot < slot,
        or {
          isCertified(NotarizationCertificate(b.reference()), msgs),
          isCertified(NotarFallbackCertificate(b.reference()), msgs)
        },
        b.slot.to(slot).subseteq(slotsSkipCertified(msgs))
      }
    )
  }
  
  pure def votedToSkip(s: Slot, msgs: Set[Message]): Set[ProcessID] =
    msgs.filter(m =>  m.msg == SkipVoteMsg(s)).map(m => m.sender)

  // Warning: vote doesn't contain parent. Assumption about parent hashed in hash?
  pure def votedToNotar(b: BlockReference, msgs: Set[Message]): Set[ProcessID] =
    msgs.filter(m => m.msg == NotarVoteMsg(b)).map(m => m.sender)

  pure def safeToNotarCondition(v: ProcessID, msgs: Set[Message], now: Slot, b: Block): bool = all {
    // Consider block b in slot s = slot(b).
    b.slot == now,

    val voted = msgs.filter(m => m.sender == v and now == slotOf(m.msg))
    val notarVoted =
      voted.filter(m => match m.msg {
        | NotarVoteMsg(m) => true
        | _ => false
      })

    and {
      voted.size() > 0,
      notarVoted.size() == 0,
    },
    val notar = votedToNotar(b.reference(), msgs)
    val skip = votedToSkip(now, msgs)
    // notar(b) ≥ 40% or (skip(s) + notar(b) ≥ 60% and notar(b) ≥ 20%).
    // Question: is (+) here the sum of the sizes or the size of the union?
    or {
      surpassesThreshold(notar, 40),
      and {
        surpassesThreshold(skip.union(notar), 60),
        surpassesThreshold(notar, 20)
      }
    }
  }

  pure def safeToSkipCondition(v: ProcessID, allMessages: Set[Message], now: Slot): bool = all {
    // node voted in slot s already, but not to skip s.
    allMessages.exists(m =>
      m.sender == v
      and slotOf(m.msg) == now
      and m.msg != SkipVoteMsg(now)
    ),

    // Moreover:
    // skip(s) + Σ_b notar(b) − max_b notar(b) ≥ 40%.
    val blocksWithNotarVotes =
      allMessages
        .filter(m => slotOf(m.msg) == now)
        .filterMap(m => match m.msg {
          | NotarVoteMsg(n) => Some(n)
          | _ => None
        })

    // Σ_b notar(b)
    val allNotarVotes = blocksWithNotarVotes.map(b =>
      votedToNotar(b, allMessages)
    ).flatten()

    // max_b
    val blockWithMostVotes = blocksWithNotarVotes.fold({ slot: -1, hash: -1 }, (res, x) => {
      if (votedToNotar(x, allMessages).size() > votedToNotar(res, allMessages).size())
        x
      else
        res
    })

    // skip(s) + Σ_b notar(b) − max_b notar(b) ≥ 40%.
    // Question: is (+) here the sum of the sizes or the size of the union?
    // same for (-)

    // skip(s)
    votedToSkip(now, allMessages)
      // + Σ_b notar(b)
      .union(allNotarVotes)
      // - max_b notar(b)
      .exclude(votedToNotar(blockWithMostVotes, allMessages))
      // ≥ 40%.
      .surpassesThreshold(40)
  }

  // -----------------------------------------------------------------------------
  // Listeners (Algorithm 1)
  // -----------------------------------------------------------------------------

  /// Listen for block input - returns parameters for process_block_input
  pure def listen_block_inputs(ctx: LocalContext): Set[Block] = {
    allBlocks.filter(b => aliveSlots.contains(b.slot))
  }

  pure def process_block_input(ctx: LocalContext, b: Block): Transition = {
    val tn = tryNotar(ctx.state, b) // looks like a function but has two side effects: changes state and broadcasts
    if (tn.success)
      val cpb = checkPendingBlocks(tn.result.post_state)
      // as tryNotar changed the local state, we pass it to checkPendingBlocks
      { post_state: cpb.post_state, effects: cpb.effects.union(tn.result.effects) }
      // both, tryNotar and checkPendingBlocks have side effects of sending messages. Thus we build the union here.
    else if (not(Voted.in(tn.result.post_state.state[b.slot])))
      { post_state: setPendingBlock(tn.result.post_state, b.slot, Some(b)), effects: tn.result.effects }
    else
      // Even if all if conditions evaluate to false, tryNotar may have side effects and may change the local state
      tn.result
  }

  /// Listen for timeout events - returns parameters for skip_window_if_voted
  pure def listen_timeouts(ctx: LocalContext): Set[Slot] = {
    val activeTimeouts = ctx.events
    aliveSlots.filter(slot => activeTimeouts.contains(slot))
  }

  pure def skip_window_if_voted(ctx: LocalContext, slot: Slot): Transition = {
    val ls = ctx.state

    if (not(Voted.in(ls.state[slot])))
      trySkipWindow(ls, slot)
    else
      // No change state, no messages sent
      { effects: Set(), post_state: ls }
  }

  /// Listen for block notarized events - returns parameters for try_finalize_block
  pure def listen_block_notarized(ctx: LocalContext): Set[{ slot: Slot, hash: Blockhash }] = {
    val notarizedBlocks = allBlocks.filter(b =>
      isCertified(NotarizationCertificate({ slot: b.slot, hash: b.hash }), ctx.messages) and
      aliveSlots.contains(b.slot)
    )

    notarizedBlocks.map(block => { slot: block.slot, hash: block.hash })
  }

  pure def try_finalize_block(ctx: LocalContext, params: { slot: Slot, hash: Blockhash }): Transition = {
    val s1 = addObjects(ctx.state, params.slot, Set(BlockNotarized(params.hash)))
    tryFinal(s1, params.slot, params.hash)
  }

  /// Listen for parent ready events - returns parameters for check_pending_and_start_timeout
  pure def listen_parent_ready(ctx: LocalContext): Set[{ slot: Slot, hash: Blockhash }] = {
    val readyBlocks = aliveSlots.map(s =>
      parentReadyBlocks(s, ctx.messages)
    ).flatten()

    readyBlocks.map(block => block.reference())
  }

  pure def check_pending_and_start_timeout(ctx: LocalContext, params: { slot: Slot, hash: Blockhash }): Transition = {
    val r1 =
      addObjects(ctx.state, params.slot, Set(ParentReady(params.hash)))
        .checkPendingBlocks()
    // Start time for all slots in this window
    val r2 = setTimeouts(r1.post_state, params.slot)
    { effects: r1.effects.union(r2.effects), post_state: r2.post_state }
  }

  /// Listen for safe to notar events - returns parameters for broadcast_fallback_notar_vote
  pure def listen_safe_to_notar(ctx: LocalContext): Set[{ slot: Slot, hash: Blockhash }] = {
    val safeBlocks = allBlocks.filter(b =>
      aliveSlots.contains(b.slot) and
      safeToNotarCondition(ctx.state.process_id, ctx.messages, b.slot, b)
    )

    safeBlocks.map(block => { slot: block.slot, hash: block.hash })
  }

  pure def broadcast_fallback_notar_vote(ctx: LocalContext, params: { slot: Slot, hash: Blockhash }): Transition = {
    val s1 = trySkipWindow(ctx.state, params.slot)
    if (not(ItsOver.in(s1.post_state.state[params.slot])))
      // Notar-fallback vote
      val effects = s1.effects.union(
        Set(choreo::Broadcast({
          sender: ctx.state.process_id,
          msg: NotarFallBackVoteMsg({ slot: params.slot, hash: params.hash })
        }))
      )
      { effects: effects, post_state: addObjects(s1.post_state, params.slot, Set(BadWindow)) }
    else
      s1
  }

  /// Listen for safe to skip events - returns parameters for broadcast_fallback_skip_vote
  pure def listen_safe_to_skip(ctx: LocalContext): Set[Slot] =
    aliveSlots.filter(slot => safeToSkipCondition(ctx.state.process_id, ctx.messages, slot))

  pure def broadcast_fallback_skip_vote(ctx: LocalContext, slot: Slot): Transition = {
    val s1 = trySkipWindow(ctx.state, slot)
    if (not(ItsOver.in(s1.post_state.state[slot])))
      // Skip-fallback vote
      val effects = s1.effects.union(
        Set(choreo::Broadcast({ sender: ctx.state.process_id, msg: SkipFallbackVoteMsg(slot) }))
      )
      { effects: effects, post_state: addObjects(s1.post_state, slot, Set(BadWindow)) }
    else
      s1
  }

  /// Main listener combining all event handlers using choreo::cue pattern
  pure def main_listener(ctx: LocalContext): Set[Transition] =
    Set(
      choreo::cue(ctx, listen_block_inputs, process_block_input),
      choreo::cue(ctx, listen_timeouts, skip_window_if_voted),
      choreo::cue(ctx, listen_block_notarized, try_finalize_block),
      choreo::cue(ctx, listen_parent_ready, check_pending_and_start_timeout),
      choreo::cue(ctx, listen_safe_to_notar, broadcast_fallback_notar_vote),
      choreo::cue(ctx, listen_safe_to_skip, broadcast_fallback_skip_vote)
    ).flatten()

  // -----------------------------------------------------------------------------
  // Choreo integration (init and step actions)
  // -----------------------------------------------------------------------------

  /// Initialize process state
  pure def initialize_process(process: ProcessID): LocalState = {
    // preload state for 5 slots
    pure val slots = 0.to(4)
    {
      process_id: process,
      pendingBlocks: slots.fold([], (acc, _) => acc.append(None)),
      state: slots.fold([], (acc, slot) => 
        if (slot == 0) {
          acc.append(Set(ParentReady(-1)))
        } else {
          acc.append(Set())
        }
      )
    }
  }

  /// Initial extensions state
  pure def initial_extensions: Extensions = {
    ch: aliveSlots.mapBy(s => Set()),
    counter: 0
  }

  action init = choreo::init({
    system: benevolent.mapBy(n => initialize_process(n)),
    messages: benevolent.mapBy(n => byzMessages),
    events: benevolent.mapBy(n => Set(0)), // initial timeout for slot 0
    extensions: initial_extensions
  })

  action step = choreo::step(
    main_listener,
    (c, _) => c
  )

  // -----------------------------------------------------------------------------
  // Invariants and properties
  // -----------------------------------------------------------------------------

  val s = choreo::s

  /// Auxiliary definition to fetch all messages
  val allMessages = s.messages.values().flatten()

  /// Agreement: no two correct processes decide on different values for the same slot
  //
  val agreement =
    aliveSlots.forall(slot => finalized(slot, allMessages).size() <= 1)

  val fastAgreement =
    aliveSlots.forall(slot => fastFinalized(slot, allMessages).union(finalized(slot, allMessages)).size() <= 1)

  // Witness was used to find bug in safeToNotar encoding
  val noBad =
    benevolent.forall(v => not(s.system.get(v).state[1].contains(BadWindow)))

  /// Witness to find a run where a block is fast finalized
  val fastFinalizedWitness =
    allBlocks.forall(b => not(isCertified(FastFinalizationCertificate(b.reference()), allMessages)))

  /// Witness to find a run where a timeout is started
  val timeoutWitness =
     s.events.values().forall(v => v == Set())

  /// Theorem 1 (safety). If any correct node finalizes a block b in slot s and any
  /// correct node finalizes any block b′ in any slot s′ ≥ s, b′ is a descendant of b.
  val safety = tuples(aliveSlots, allBlocks).forall(((slot, block)) => {
    val finalizedAtSlot = finalized(slot, allMessages)
    block.hash.in(finalizedAtSlot) implies tuples(
      aliveSlots.filter(s2 => s2 >= slot), allBlocks).forall(((slot2, block2)) => {
      block2.hash.in(finalized(slot2, allMessages)) implies block2.isDescendant(block)
    })
  })

  /// This generates example traces where a block is finalized after some empty slots
  /// increase max steps to approx 100.
  val emptySlotsWitness =
    aliveSlots.forall(s1 =>
      aliveSlots.forall(s2 =>
        s1 < s2 implies
      s.extensions.ch.get(s1).size() >= s.extensions.ch.get(s2).size()))

  /// This generates example traces where every slot is finalized
  /// increase max steps to approx 100.
  val noEmptySlotsWitness =
    aliveSlots.exists(s1 =>
      s.extensions.ch.get(s1).size() == 0)

  // TODO finalize ancestors locally

  // -----------------------------------------------------------------------------
  // Setup for runs
  // -----------------------------------------------------------------------------

  def with_cue(process, listen_fn, params) =
    choreo::with_cue(process, listen_fn, params)

  action perform(cue_ctx, upon_fn) =
    choreo::perform(cue_ctx, upon_fn, (c, _) => c)
}

module some_byz {
  // For a trace where a value is fast finalized call
  // quint run alpenglow.qnt --main some_byz --invariant fastFinalizedWitness
  import alpenglow(
    correct = Set("v1", "v2", "v3", "v4", "v5"),
    good = Set(),
    byzantine = Set("b1"),
    power = Set("v1", "v2", "v3", "v4", "v5", "b1").mapBy(_ => 1),
    correctBlocks = Set(
      { slot: 0, hash: 42, parent: -1 },
      { slot: 1, hash: 43, parent: 42 },
      { slot: 2, hash: 44, parent: 43 },
    ),
    byzantineBlocks = Set(
      { slot: 1, hash: 46, parent: 42 },
      { slot: 1, hash: 47, parent: 45 },
      { slot: 2, hash: 48, parent: 43 },
      { slot: 2, hash: 49, parent: 45 },
    ),
    aliveSlots = 0.to(2),
    aliveHashes = 42.to(49),
  ).*

  run ffTest =
    pure val block = { hash: 42, parent: -1, slot: 0 }
    init
      .then("v1".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v2".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v3".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v4".with_cue(listen_block_inputs, block).perform(process_block_input))
      .expect(fastFinalized(0, allMessages) == Set(42))
}

module some_byz_vp {
  // This module sets different voting powers
  // For a trace where a value is fast finalized call
  // quint run alpenglow.qnt --main some_byz_vp --invariant fastFinalizedWitness
  import alpenglow(
    correct = Set("v1", "v2"),
    good = Set(),
    byzantine = Set("b1"),
    power = Map("v1" -> 3, "v2" -> 2, "b1"-> 1),
    correctBlocks = Set(
      { slot: 0, hash: 42, parent: -1 },
      { slot: 1, hash: 43, parent: 42 },
      { slot: 2, hash: 44, parent: 43 },
    ),
    byzantineBlocks = Set(
      { slot: 1, hash: 46, parent: 42 },
      { slot: 1, hash: 47, parent: 45 },
      { slot: 2, hash: 48, parent: 43 },
      { slot: 2, hash: 49, parent: 45 },
    ),
    aliveSlots = 0.to(2),
    aliveHashes = 42.to(49),
  ).*

  run ffTest =
    pure val block = { hash: 42, parent: -1, slot: 0 }
    init
      .then("v1".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v2".with_cue(listen_block_inputs, block).perform(process_block_input))
      .expect(fastFinalized(0, allMessages) == Set(42))
}

module too_many_byz_1 {
  // to violate agreement, run
  // quint run alpenglow.qnt --main too_many_byz_1 --invariant agreement

  import alpenglow(
    correct = Set("v1", "v2", "v3", "v4"),
    good = Set(),
    byzantine = Set("b1"),
    power = Set("v1", "v2", "v3", "v4", "b1").mapBy(_ => 1),
    correctBlocks = Set(
      { slot: 0, hash: 42, parent: -1 },
      { slot: 1, hash: 43, parent: 42 },
      { slot: 2, hash: 44, parent: 43 },
    ),
    byzantineBlocks = Set(
      { slot: 0, hash: 45, parent: -1 },
      { slot: 1, hash: 46, parent: 42 },
      { slot: 1, hash: 47, parent: 45 },
      { slot: 2, hash: 48, parent: 43 },
      { slot: 2, hash: 49, parent: 45 },
    ),
    aliveSlots = 0.to(2),
    aliveHashes = 42.to(49),
  ).*
}

module too_many_byz {
  import basicSpells.* from "./spells/basicSpells"

  // to violate agreement, run
  // quint run alpenglow.qnt --main too_many_byz --invariant agreement

  import alpenglow(
    correct = Set("v1", "v2", "v3", "v4"),
    good = Set(),
    byzantine = Set("b1", "b2"),
    power = Set("v1", "v2", "v3", "v4", "b1", "b2").mapBy(_ => 1),
    correctBlocks = Set({ slot: 0, hash: 42, parent: -1 }),
    byzantineBlocks = Set({ slot: 0, hash: 41, parent: -1 }),
    aliveSlots = Set(0),
    aliveHashes = 41.to(42),
  ).*

  run disagreementTest =
    init
      .then("v3".with_cue(listen_block_inputs, { hash: 41, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v4".with_cue(listen_block_inputs, { hash: 41, parent: -1, slot: 0 }).perform(process_block_input))

      .expect(
        Set(
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "v3" },
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "v4" },
        ).subseteq(allMessages)
      )

      .then("v2".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v3".with_cue(listen_block_notarized, { slot: 0, hash: 41 }).perform(try_finalize_block))
      .then("v4".with_cue(listen_block_notarized, { slot: 0, hash: 41 }).perform(try_finalize_block))
      .expect(
        Set(
          { msg: FinalVoteMsg(0), sender: "v3" },
          { msg: FinalVoteMsg(0), sender: "v4" }
        ).subseteq(allMessages)
      )

      .then("v1".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .expect(not(agreement))
      .expect(
        Set(
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "v3" },
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "v4" },
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "b1" },
          { msg: NotarVoteMsg({ hash: 41, slot: 0 }), sender: "b2" },
          { msg: NotarVoteMsg({ hash: 42, slot: 0 }), sender: "v1" },
          { msg: NotarVoteMsg({ hash: 42, slot: 0 }), sender: "v2" },
          { msg: NotarVoteMsg({ hash: 42, slot: 0 }), sender: "b1" },
          { msg: NotarVoteMsg({ hash: 42, slot: 0 }), sender: "b2" },
          { msg: FinalVoteMsg(0), sender: "v3" },
          { msg: FinalVoteMsg(0), sender: "v4" },
          { msg: FinalVoteMsg(0), sender: "b1" },
          { msg: FinalVoteMsg(0), sender: "b2" }
        ).subseteq(allMessages)
      )
}
