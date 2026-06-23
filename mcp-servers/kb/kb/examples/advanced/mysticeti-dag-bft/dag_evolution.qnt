
/**
 * A state machine for how a DAG can evolve over time.
 * Built to check Mysticeti [1] consensus, but should be generalizable
 * to any DAG-based consensus.
 *
 * [1]: https://arxiv.org/pdf/2310.14821
 *
 * Martin Hutle and Gabriela Moreira, Informal Systems, 2024-2025
 */
module dag_evolution {
  import basicSpells.* from "./spells/basicSpells"

  type BlockReference = { authority: int, round: int, index: int }
  type StatementBlock = { reference: BlockReference, parents: Set[BlockReference] }

  type DAG = Set[StatementBlock]

  pure val FAULTY = 1
  pure val CORRECT_NODES = Set(0, 1, 2)
  pure val NODES = CORRECT_NODES.union(Set(3))

  type NodeState = {
    authority: int,
    dag: DAG,
    backlog: Set[StatementBlock],
    current_round: int,
    incoming_messages: Set[StatementBlock]
  }

  var nodes: int -> NodeState
  /// A map from each authority to its leader rank, for every round (roud = list index)
  var leader_ranks: List[int -> int]
  /// The round at which we reach Global Stabilization Time (GST)
  var GST_round: int

  /// A node will only add a block to its DAG if all its parents are in the DAG already
  pure def can_add(dag: DAG, block: StatementBlock): bool = {
    pure val b_round = block.reference.round
    if (b_round == 0) {
      true
    } else {
      pure val block_references_from_previous_round = dag
        .filter(b => b.reference.round == b_round - 1)
        .map(b => b.reference)

      block.parents.subseteq(block_references_from_previous_round)
    }
  }

  /// Whether a block has received a sufficient number of blocks for a round.
  /// Since we need 2F + 1 supporters on the oonsensus algorithm, the block needs to have
  /// least that number of blocks to start processing a new round.
  pure def has_enough_blocks(dag: DAG, round: int): bool = {
    dag.filter(b => b.reference.round == round).size() >= 2 * FAULTY + 1
  }

  /// All correct nodes have a block for this round in the DAG
  pure def stabilized(dag: DAG, round: int): bool = {
    CORRECT_NODES.subseteq(
      dag.filter(b => b.reference.round == round).map(b => b.reference.authority)
    )
  }

  /// Add the block to the DAG if possible, otherwise add to the backlog and retry later
  pure def receive_block(node: NodeState, block: StatementBlock): NodeState = {
    if (can_add(node.dag, block)) {
      { ...node, dag: node.dag.union(Set(block)) }
    } else {
      { ...node, backlog: node.backlog.union(Set(block)) }
    }
  }

  /// Receive blocks that couldn't be received before and were stored to the backlog
  pure def consume_backlog(node: NodeState): NodeState = {
    pure val highest_round = node.dag.map(b => b.reference.round).fold(0, max)

    // Incrementally add blocks, starting from lowest rounds
    pure val new_dag = range(0, highest_round).foldl(node.dag, (updated_dag, r) => {
      pure val to_add = updated_dag.filter(b => b.reference.round == r and can_add(node.dag, b))
      updated_dag.union(to_add)
    })

    { ...node, dag: new_dag, backlog: node.backlog.exclude(new_dag) }
  }

  /// Broadcasts a message with a new block
  pure def send_correct_message(states: int -> NodeState, block: StatementBlock): int -> NodeState = {
    states.keys().fold(states, (acc, authority) => {
      acc.setBy(authority, s => { ...s, incoming_messages: s.incoming_messages.union(Set(block)) })
    })
  }

  // Sends byzantine messages, potentially dropping messages, links and/or corrupting messages
  pure def send_byzantine_message(
    states: int -> NodeState,
    block: StatementBlock,
    bad_indexes: int -> int,
    drops_links: int -> bool,
    drops_all: int -> bool
  ): int -> NodeState = {
    states.keys().fold(states, (acc, auth) => {
      if (drops_all.get(auth)) {
        // drop whole message
        acc        
      } else if (drops_links.get(auth)) {
        // parent list dropped, messages potentially corrupted
        pure val byzblock = {
          reference: { ...block.reference, index: bad_indexes.get(auth)},
          parents: Set()
        }
        acc.setBy(auth, s => { ...s, incoming_messages: s.incoming_messages.union(Set(byzblock)) })     
      } else {
        // parent list dropped, messages potentially corrupted, 0 means correct
        pure val byzblock = {
          reference: { ...block.reference, index: bad_indexes.get(auth) },
          parents: block.parents
        }
        acc.setBy(auth, s => { ...s, incoming_messages: s.incoming_messages.union(Set(byzblock)) })     
      }
    })
  }

  /// Whether a node is ready to propose a new block in a new round.
  /// Always true for the first round (zero)
  /// If we reached GST, then we need to check if the DAG is stabilized
  /// Otherwise, we check if the node has enough blocks for the round it is in
  def can_go_to_new_round(node: NodeState): bool = {
    node.current_round == 0 or if (GST) {
      stabilized(node.dag, node.current_round)
    } else {
      has_enough_blocks(node.dag, node.current_round)
    }
  }

  action new_round(node: NodeState): bool = all {
    can_go_to_new_round(node),
    val updated_nodes = nodes.setBy(node.authority, n => { ...n, current_round: node.current_round + 1 })
    val new_block = {
        reference: {
          authority: node.authority,
          round: node.current_round + 1,
          index: 0,
        },
        parents: node.dag.filter(b => b.reference.round == node.current_round).map(b => b.reference)
    }
    all {
      elect_leaders(new_block.reference.round),
      if (CORRECT_NODES.contains(node.authority))
        nodes' = send_correct_message(updated_nodes, new_block)
      else
        nondet random = NODES.setOfMaps(Set(0,1,2,3)).oneOf() 
        nondet drops_links = NODES.setOfMaps(Set(true,false)).oneOf()
        nondet drops_all = NODES.setOfMaps(Set(true,false)).oneOf()
        nodes' = send_byzantine_message(updated_nodes, new_block, random, drops_links, drops_all)
    }
  }

  /// A set of possible leader ranks for a round. That is, a maping from authorities to ranks,
  /// where all ranks are different
  pure val possible_leader_ranks =
    NODES.setOfMaps(0.to(NODES.size())).filter(m => m.values().size() == NODES.size())

  action elect_leaders(round) = {
    if (round > leader_ranks.length()) {
      nondet new_leader_ranks = possible_leader_ranks.oneOf()
      leader_ranks' = leader_ranks.append(new_leader_ranks)
    } else {
      // Already elected leaders for this round (saved to leader_ranks[round - 1])
      leader_ranks' = leader_ranks
    }
  }

  val GST = nodes.values().forall(n => n.current_round >= GST_round)

  action init = all {
    nodes' = NODES.mapBy(n => {
      authority: n,
      dag: Set(),
      backlog: Set(),
      current_round: 0,
      incoming_messages: Set()
    }),
    nondet leader_ranks_0 = possible_leader_ranks.oneOf()
    leader_ranks' = [leader_ranks_0],
    nondet round_GST = 1.to(5).oneOf()
    GST_round' = round_GST,
  }

  val pending_nodes = nodes.values().filter(node => {
    node.incoming_messages != Set() or (node.backlog != Set() and consume_backlog(node) != node)
  })

  val nodes_that_can_go_to_new_round = nodes.values().filter(can_go_to_new_round)

  /// Follow a prioritization order to avoid having low odds to make progress.
  /// This is important since we require a high number of steps and the simulator
  /// gives up too easily if actions are not enabled.
  action step = all {
    if (pending_nodes != Set()) all {
      nondet node = pending_nodes.oneOf()
      if (node.incoming_messages != Set()) {
        nondet block = node.incoming_messages.oneOf()
        nodes' = nodes
          .set(node.authority, { ...receive_block(node, block), incoming_messages: node.incoming_messages.exclude(Set(block)) })
      } else {
        nodes' = nodes.setBy(node.authority, n => consume_backlog(n))
      },
      leader_ranks' = leader_ranks,
    } else if (nodes_that_can_go_to_new_round != Set()) all {
      nondet node = nodes_that_can_go_to_new_round.oneOf()
      new_round(node),
    } else all {
      false,
      nodes' = nodes,
      leader_ranks' = leader_ranks,
    },
    GST_round' = GST_round,
  }

  /// Witness to check if we are progressing often enough
  val witness = nodes.values().forall(n => not(n.dag.exists(b => b.reference.round > 5)))
}
