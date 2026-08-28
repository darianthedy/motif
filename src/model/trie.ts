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
  /**
   * Accepted solver moves, each mapped to its variants: one per distinct
   * opponent answer, in declaration order.
   *
   * A move needs more than one node behind it because the opponent's answer is
   * part of the position the next move is judged against. A mate in two where
   * both defences are written out — `Qg6 Rf7 Qxf7#` and `Qg6 hxg6 Ng7#` — shares
   * the key move and nothing after it: `Ng7` mates only in the line where the
   * pawn took. Collapsing the two onto one node would play one defence on the
   * board and accept the other line's finish against it.
   *
   * Only the first variant is reachable, because only one answer can be played;
   * the rest are kept so that adding an alternative defence to a puzzle can
   * never silently widen what the played line accepts.
   */
  edges: Map<Uci, TrieEdge[]>;
  /**
   * The move from the earliest-declared solution reaching this node. Hints use
   * it, so a hint is the author's mainline rather than whichever move happens
   * to be first in map iteration order.
   */
  preferredMove: Uci | null;
}

export interface TrieEdge {
  /**
   * The opponent's scripted reply, or null when nothing answers this move.
   *
   * Not the same question as whether the line ends: a line may end *on* the
   * reply, in which case this is set and `next` is terminal. Ending is
   * `isTerminal(next)`, and only that.
   */
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

      let variants = node.edges.get(solverMove);
      if (!variants) {
        variants = [];
        node.edges.set(solverMove, variants);
      }

      // A line that declares no reply does so because it stopped, not because
      // it claims the opponent is out of moves — so it joins the first variant
      // rather than forking one of its own. Conversely a line that names a reply
      // fills the blank a shorter line left, so the board never sits a ply
      // behind the position the next expected move is written for. Only two
      // lines that name *different* replies fork, because only then do they
      // reach different positions.
      const existing =
        reply === null
          ? variants[0]
          : (variants.find((edge) => edge.reply === reply) ??
            variants.find((edge) => edge.reply === null));

      let edge = existing;
      if (edge) {
        edge.reply ??= reply;
      } else {
        edge = { reply, next: emptyNode() };
        variants.push(edge);
      }
      node = edge.next;
    }
  }

  return root;
}

/**
 * Looks up a solver move, applying the queening fallback described on
 * `stripQueenPromotion`.
 *
 * Returns the first variant: the opponent's answer is the author's, from the
 * earliest line declaring one, the same way `preferredMove` is.
 */
export function findEdge(node: TrieNode, move: Uci): TrieEdge | null {
  const exact = node.edges.get(move);
  if (exact?.length) return exact[0];

  const stripped = stripQueenPromotion(move);
  if (!stripped) return null;
  return node.edges.get(stripped)?.[0] ?? null;
}

/** Every accepted first move, for the "other solutions" disclosure. */
export function alternativeCount(root: TrieNode): number {
  return Math.max(0, root.edges.size - 1);
}
