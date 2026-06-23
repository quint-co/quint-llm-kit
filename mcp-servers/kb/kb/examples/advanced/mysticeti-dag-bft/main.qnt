
/**
 * A module to check invariants of the Mysticeti consensus algorithm [1] over an evolving DAG
 *
 * [1]: https://arxiv.org/pdf/2310.14821
 *
 * Gabriela Moreira, Informal Systems, 2025
 */
module main {
  import basicSpells.* from "spells/basicSpells"
  import dag_evolution.* from "dag_evolution"
  import mysticeti_c from "mysticeti_c"
  import mysticeti_types.to_block_store from "mysticeti_c"

  /// Function to convert a reference from the dag_evolution format to the mysticeti_c format
  /// by dropping the "index" and adding a "label"
  def convert_reference(b) = {
      {
        authority: b.authority,
        round: b.round,
        label: "Generated",
        leader_rank: leader_ranks[b.round - 1].get(b.authority),
        // we might need to add the index when we have equivocation
      }
  }

  /// The nodes map with converted references, to be used in mysticeti_c operators
  val dags_for_consensus = nodes.transformValues(node => {
    node.dag.map(b => {
      reference: b.reference.convert_reference(),
      parents: b.parents.map(convert_reference),
    })
  })

  /// Lemma 7. All correct validators commit a consistent sequence of proposer
  /// blocks (i.e., the committed proposer sequence of one correct validator is
  /// a prefix of another’s).
  /// Theorem 1 (Total Order). MYSTICETI-C satisfies the total order property of
  /// Byzantine Atomic Broadcast. Theorem 1 follows directly from Lemma 7.
  val inv = {
    val orders = dags_for_consensus.values().map(dag => {
      mysticeti_c::commit_order(mysticeti_c::try_decide_all(dag.to_block_store()))
    })
    tuples(orders, orders).forall(((order1, order2)) => {
      order1.length() <= order2.length() implies order1.isPrefixOf(order2)
    })
  }
}

