
module protocolTest {
  // 1. IMPORT PROTOCOL WITH PARAMETERS
  import protocol(
    PARAM1 = value1,
    PARAM2 = value2,
    NODES = Set("node1", "node2", "node3"),
    // Add your protocol parameters here
  ).* from "./protocol"
  import basicSpells.* from "spells/basicSpells"

  // 2. TEST 1: BASIC HAPPY-PATH
  // Test the simplest successful execution path
  run basicHappyPathTest = {
    // Define test data
    val message1 = { field: value, src: "node1", round: 0 }

    init
    // Execute actions on each node
    .then("node1".with_cue(listener_name, message1).perform(action_name))
    .then("node2".with_cue(listener_name, message1).perform(action_name))
    .then("node3".with_cue(listener_name, message1).perform(action_name))
    // Verify expected state
    .expect(s.system.get("node1").stage == ExpectedStage)
  }

  // 3. TEST 2: TIMEOUT SCENARIO
  // Test timeout handling and recovery
  run timeoutRecoveryTest = {
    init
    // All nodes timeout
    .then("node1".step_with(on_timeout_listener))
    .then("node2".step_with(on_timeout_listener))
    .then("node3".step_with(on_timeout_listener))
    // Verify state after timeout
    .expect(NODES.forall(n => s.system.get(n).round == 1))
  }

  // 4. TEST 3: MESSAGE INJECTION
  // Test behavior when receiving higher-round messages
  run messageInjectionTest = {
    // Create messages to inject
    val high_round_msg1 = { src: "node1", round: 2, data: value }
    val high_round_msg2 = { src: "node2", round: 2, data: value }
    val msg1_wrapped = MessageType(high_round_msg1)
    val msg2_wrapped = MessageType(high_round_msg2)

    init
    // Inject message and execute filtered listener
    .then(
      "node3".step_with_messages(
        (ctx) => listener_name(ctx)
          .filter(msg => msg.src == high_round_msg1.src and msg.round == high_round_msg1.round)
          .map(msg => action_on_message(ctx, msg)),
        (msgs) => msgs.setAdd(msg1_wrapped)
      )
    )
    .then(
      "node3".step_with_messages(
        (ctx) => listener_name(ctx)
          .filter(msg => msg.src == high_round_msg2.src and msg.round == high_round_msg2.round)
          .map(msg => action_on_message(ctx, msg)),
        (msgs) => msgs.setAdd(msg2_wrapped)
      )
    )
    // Verify effect of injected messages
    .expect(and {
      s.system.get("node3").round == 2,
      s.system.get("node3").stage == ExpectedStage
    })
  }

  // 5. TEST 4: MULTI-STAGE WORKFLOW
  // Test complete workflow through multiple stages
  run multiStageWorkflowTest = {
    // Initial message
    val initial_msg = { data: "value", round: 0, src: "node1" }

    init
    // Stage 1: All nodes process initial message
    .then("node1".with_cue(listener_stage1, initial_msg).perform(action_stage1))
    .then("node2".with_cue(listener_stage1, initial_msg).perform(action_stage1))
    .then("node3".with_cue(listener_stage1, initial_msg).perform(action_stage1))
    // Stage 2: Extract and process resulting messages
    .then(
      // Extract message created by stage 1
      val stage1_result = s.messages.get("node1").get_message_type()
        .find(m => m.round == 0 and m.src == "node1")
        .unwrap()

      "node1".with_cue(listener_stage2, stage1_result).perform(action_stage2)
        .then("node2".with_cue(listener_stage2, stage1_result).perform(action_stage2))
        .then("node3".with_cue(listener_stage2, stage1_result).perform(action_stage2))
        // Verify final state
        .expect(NODES.forall(n => s.system.get(n).stage == FinalStage))
    )
  }

  // 6. TEST 5: COMPLEX SCENARIO WITH NESTED DATA
  // Test with complex message extraction and validation
  run complexScenarioTest = {
    // Build complex test data
    val justification = Set(
      { src: "node1", round: 0, data: "value1" },
      { src: "node2", round: 0, data: "value1" },
      { src: "node3", round: 0, data: "value2" }
    )
    val wrapped_msgs = justification.map(m => MessageType(m))

    init
    // Setup: Advance one node to special stage
    .then("node1".step_deterministic(ctx => advance_to_stage(ctx, SpecialStage)))
    .expect(s.system.get("node1").stage == SpecialStage)
    // Main action: Process with injected justification
    .then(
      "node1".step_with_messages(
        (ctx) => listener_with_justification(ctx)
          .filter(js => js == justification)
          .map(js => action_with_justification(ctx, js)),
        (msgs) => msgs.union(wrapped_msgs)
      )
    )
    // Verify complex properties
    .expect(
      val result = s.messages.get("node1").get_message_type()
        .find(m => m.round == 0 and m.src == "node1")
        .unwrap()
      and {
        s.system.get("node1").stage == NextStage,
        result.data == "expected_value",
        validation_predicate(result)
      }
    )
  }

  // 7. HELPER PATTERNS FOR YOUR TESTS

  // Pattern: Broadcast to all nodes
  // run broadcastTest = {
  //   val msg = { ... }
  //   init
  //   .then(NODES.fold(init, (acc, node) =>
  //     acc.then(node.with_cue(listener, msg).perform(action))
  //   ))
  // }

  // Pattern: Extract and verify messages
  // .expect(
  //   val msgs = s.messages.get("node1").get_type()
  //   msgs.exists(m => m.field == expected_value)
  // )

  // Pattern: Verify all nodes in same state
  // .expect(NODES.forall(n => s.system.get(n).field == expected_value))

  // Pattern: Verify message presence
  // .expect(s.messages.get("node1").contains(MessageType(data)))
}
