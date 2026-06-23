
module alpenglow_tests {
  // quint test alpenglow_tests.qnt

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
  ).* from "alpenglow"

  run processedBlockInputTest =
    pure val block = { hash: 42, parent: -1, slot: 0 }
    init
      .then("v1".with_cue(listen_block_inputs, block).perform(process_block_input))
      .expect(
        // Expect NotarVoteMsg was broadcasted (indicates process_block_input was executed)
        allMessages.contains({ sender: "v1", msg: NotarVoteMsg({ slot: 0, hash: 42 }) })
      )

  run skippedWindowIfVotedTest =
    init
      .then("v1".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .expect(
        // Expect SkipVoteMsg was broadcasted (indicates skip_window_if_voted was executed)
        allMessages.contains({ sender: "v1", msg: SkipVoteMsg(0) })
      )

  run triedFinalizeBlockTest =
    pure val block = { hash: 42, parent: -1, slot: 0 }
    init
      .then("v1".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v2".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v3".with_cue(listen_block_inputs, block).perform(process_block_input))
      .then("v1".with_cue(listen_block_notarized, { slot: 0, hash: 42 }).perform(try_finalize_block))
      .expect(
        // Expect BlockNotarized object added to v1's state (indicates try_finalize_block was executed)
        s.system.get("v1").state[0].contains(BlockNotarized(42))
      )

  run broadcastedFallbackNotarVoteTest =
    init
      .then("v1".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v2".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v3".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v1".with_cue(listen_safe_to_notar, { slot: 0, hash: 42 }).perform(broadcast_fallback_notar_vote))
      .expect(
        // Expect NotarFallBackVoteMsg was broadcasted (indicates broadcast_fallback_notar_vote was executed)
        allMessages.contains({ sender: "v1", msg: NotarFallBackVoteMsg({ slot: 0, hash: 42 }) })
      )

  run broadcastedFallbackSkipVoteTest =
    init
      .then("v1".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v1".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v2".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v3".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v4".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v1".with_cue(listen_safe_to_skip, 0).perform(broadcast_fallback_skip_vote))
      .expect(
        // Expect SkipFallbackVoteMsg was broadcasted (indicates broadcast_fallback_skip_vote was executed)
        allMessages.contains({ sender: "v1", msg: SkipFallbackVoteMsg(0) })
      )

  run parentReadyTest =
    init
      .then("v1".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v3".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v5".with_cue(listen_timeouts, 0).perform(skip_window_if_voted))
      .then("v2".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v4".with_cue(listen_block_inputs, { hash: 42, parent: -1, slot: 0 }).perform(process_block_input))
      .then("v5".with_cue(listen_safe_to_notar, { slot: 0, hash: 42 }).perform(broadcast_fallback_notar_vote))
      .then("v1".with_cue(listen_parent_ready, { slot: 0, hash: 42 }).perform(check_pending_and_start_timeout))
      .expect(
        // Expect ParentReady object added to v1's state (indicates check_pending_and_start_timeout was executed)
        s.system.get("v1").state[0].contains(ParentReady(42))
      )
}
