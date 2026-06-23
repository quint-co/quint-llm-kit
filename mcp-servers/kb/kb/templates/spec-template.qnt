
module System {
  // 1. TYPES - Define your data structures
  type Address = str
  type Amount = int

  // Always use a State type to encapsulate everything
  type State = {
    field1: SomeType,
    field2: Address -> Amount,
    users: Set[Address]
  }

  // 2. CONSTANTS - Configuration values
  pure val INITIAL_BALANCE = 1000
  pure val INITIAL_USERS = Set("alice", "bob", "charlie")

  // 3. PURE FUNCTIONS - All business logic goes here
  /// Core operation logic - pure function does ALL the work
  pure def calculateOperation(
    state: State,
    user: Address,
    params: SomeParams
  ): {success: bool, newState: State} = {
    // Validation
    val canPerform = state.users.contains(user) and /* other checks */

    if (canPerform) {
      // Calculate new state
      val newField1 = /* computation */
      val newField2 = state.field2.put(user, /* new value */)

      {
        success: true,
        newState: { ...state, field1: newField1, field2: newField2 }
      }
    } else {
      {success: false, newState: state}
    }
  }

  // 4. STATE VARIABLES
  var field1: SomeType
  var field2: Address -> Amount
  var users: Set[Address]

  // Helper to get current state
  val currentState = {
    field1: field1,
    field2: field2,
    users: users
  }

  // 5. INVARIANTS - What should always be true
  val noNegativeBalances = users.forall(u => field2.get(u) >= 0)

  // 6. ACTIONS - Thin wrappers that call pure functions
  action unchanged_all = all {
    field1' = field1,
    field2' = field2,
    users' = users
  }

  // 6.1. ACTION WITNESSES - Reachability tests for action execution
  /// Check if operations can execute successfully (action witness should be violated)
  val canPerformOperationSuccessfully = not(lastActionSuccess and /* evidence of successful operation */)
  /// Check if complex workflow can complete (action witness should be violated)
  val canCompleteWorkflow = not(/* state indicating successful completion */)

  action performOperation(user: Address, params: SomeParams): bool = {
    val result = calculateOperation(currentState, user, params)

    if (result.success) {
      all {
        field1' = result.newState.field1,
        field2' = result.newState.field2,
        users' = result.newState.users
      }
    } else {
      unchanged_all
    }
  }

  // 7. INITIALIZATION
  action init = all {
    field1' = initialValue,
    field2' = INITIAL_USERS.mapBy(user => INITIAL_BALANCE),
    users' = INITIAL_USERS
  }

  // 8. STEP ACTION
  action step = {
    nondet user = INITIAL_USERS.oneOf()
    nondet param = 1.to(100).oneOf()

    any {
      performOperation(user, param),
      // other operations
    }
  }
}
