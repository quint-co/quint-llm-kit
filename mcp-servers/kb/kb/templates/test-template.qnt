
module systemTest {
  import System.* from "./system"

  /// Working concrete test
  run basicOperationTest = {
    init
    .expect(
      // Check initial state
      and {
        field1 == initialValue,
        users.size() == 3,
        field2.get("alice") == INITIAL_BALANCE
      }
    )
    .then(
      performOperation("alice", 42)
    )
    .expect(
      // Check expected result
      and {
        field1 == expectedValue,
        field2.get("alice") == expectedBalance
      }
    )
  }

  /// Non-deterministic test (fix later if needed)
  run variableTest = {
    nondet user = INITIAL_USERS.oneOf()
    nondet amount = 1.to(100).oneOf()

    init
    .then(performOperation(user, amount))
    .expect(
      // Flexible expectations
      and {
        field2.get(user) >= 0,  // Basic safety
        users.contains(user)     // User still exists
      }
    )
  }
}
