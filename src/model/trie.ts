import { stripQueenPromotion } from './move';
import type { Uci } from './move';

/**
 * The set of accepted continuations for one puzzle, as a tree.
 *
 * Every node is a position awaiting the *solver's* move. An edge is one
 * accepted solver move, carrying the opponent's scripted answer to it.
 * Solutions sharing a prefix collapse into shared nodes automatically, so two
 * lines diverging at move three need no special handling — and a position where
 * several solver moves win is just a node with several edges.
 *
 * The alternative, a list of lines checked in parallel, has to track which
 * lines are still alive after every move and answer "which opponent reply now?"
 * when several disagree. The tree makes both questions structural.
 */
export interface TrieNode {
  edges: Map<Uci, TrieEdge>;
  /**
   * The move from the earliest-declared solution reaching this node. Hints use
   * it, so a hint is the author's mainline rather than whichever move happens
   * to be first in map iteration order.
   */
  preferredMove: Uci | null;
}

export interface TrieEdge {
  /** The opponent's scripted reply, or null when the line ends here. */
  reply: Uci | null;
  next: TrieNode;
}

function emptyNode(): TrieNode {
  return { edges: new Map(), preferredMove: null };
}

export function isTerminal(node: TrieNode): boolean {
  return node.edges.size === 0;
}

export function buildTrie(solutions: Uci[][]): TrieNode {
  const root = emptyNode();

  for (const line of solutions) {
    let node = root;
    for (let ply = 0; ply < line.length; ply += 2) {
      const solverMove = line[ply];
      const reply = ply + 1 < line.length ? line[ply + 1] : null;
      if (node.preferredMove === null) node.preferredMove = solverMove;

      const existing = node.edges.get(solverMove);
      if (existing) {
        node = existing.next;
      } else {
        const next = emptyNode();
        node.edges.set(solverMove, { reply, next });
        node = next;
      }
    }
  }

  return root;
}

/**
 * Looks up a solver move, applying the queening fallback described on
 * `stripQueenPromotion`.
 */
export function findEdge(node: TrieNode, move: Uci): TrieEdge | null {
  const exact = node.edges.get(move);
  if (exact) return exact;

  const stripped = stripQueenPromotion(move);
  return stripped ? (node.edges.get(stripped) ?? null) : null;
}

/** Every accepted first move, for the "other solutions" disclosure. */
export function alternativeCount(root: TrieNode): number {
  return Math.max(0, root.edges.size - 1);
}
