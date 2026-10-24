/**
 * How a game is named in a list, from its headers. PGN marks an unknown value
 * with `?`, which is the same as no value for anything shown here.
 */

const known = (value: string | undefined): string | undefined => {
  const trimmed = value?.trim();
  return trimmed && !/^[?.]*$/.test(trimmed) ? trimmed : undefined;
};

/** `2024.03.??` reads as `2024.03`. */
function date(value: string | undefined): string | undefined {
  const kept: string[] = [];
  for (const part of (value ?? '').split('.')) {
    if (!/^\d+$/.test(part)) break;
    kept.push(part);
  }
  return kept.length ? kept.join('.') : undefined;
}

/** `Carlsen – Nakamura`, or the event when the players are not known. */
export function gameTitle(headers: Record<string, string>): string {
  const white = known(headers.White);
  const black = known(headers.Black);
  if (white || black) return `${white ?? '?'} – ${black ?? '?'}`;
  return known(headers.Event) ?? 'Untitled game';
}

/** `1-0 · Tata Steel · 2024.01` — whatever of those is known. */
export function gameSubtitle(headers: Record<string, string>): string {
  const result = headers.Result && headers.Result !== '*' ? headers.Result : undefined;
  const players = known(headers.White) || known(headers.Black);
  return [
    result,
    players ? known(headers.Event) : undefined,
    known(headers.Opening) ?? known(headers.ECO),
    date(headers.Date),
  ]
    .filter(Boolean)
    .join(' · ');
}

const SEARCHED = ['White', 'Black', 'Event', 'Site', 'Date', 'Round', 'Opening', 'ECO', 'Annotator'];

/** Whether every word of `query` is in one of the headers people search by. */
export function matchesSearch(headers: Record<string, string>, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return true;
  const text = SEARCHED.map((name) => headers[name] ?? '')
    .join(' ')
    .toLowerCase();
  return words.every((word) => text.includes(word));
}

/** How a numeric annotation is shown. Ones without a usual symbol are left out. */
export { NAG_SYMBOLS } from './pgn';

/**
 * A comment as it reads. Exports from the big sites carry `[%clk 0:03:12]`
 * and `[%eval 0.4]` commands in their comments, for their own boards; they are
 * kept in the PGN and left out here.
 */
export function displayComment(comment: string | undefined): string {
  return (comment ?? '').replace(/\[%[^\]]*\]/g, '').replace(/\s+/g, ' ').trim();
}
