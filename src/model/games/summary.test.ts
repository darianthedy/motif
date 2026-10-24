import { describe, expect, it } from 'vitest';
import { displayComment, gameSubtitle, gameTitle, matchesSearch } from './summary';

describe('naming a game in a list', () => {
  it('names it by its players', () => {
    expect(gameTitle({ White: 'Carlsen', Black: 'Nakamura' })).toBe('Carlsen – Nakamura');
    expect(gameTitle({ White: 'Carlsen', Black: '?' })).toBe('Carlsen – ?');
  });

  it('falls back to the event, then to nothing known', () => {
    expect(gameTitle({ White: '?', Black: '?', Event: 'Endgame study' })).toBe('Endgame study');
    expect(gameTitle({ White: '?', Event: '?' })).toBe('Untitled game');
  });

  it('says what else is known underneath', () => {
    expect(
      gameSubtitle({ White: 'A', Result: '1-0', Event: 'Open', ECO: 'C65', Date: '2024.03.??' }),
    ).toBe('1-0 · Open · C65 · 2024.03');
    expect(gameSubtitle({ Result: '*', Date: '????.??.??' })).toBe('');
    // Already the title when there are no players.
    expect(gameSubtitle({ Event: 'Open', Result: '0-1' })).toBe('0-1');
  });
});

describe('searching games', () => {
  const headers = { White: 'Magnus Carlsen', Black: 'Hikaru Nakamura', Event: 'Tata Steel' };

  it('matches every word, in any header, ignoring case', () => {
    expect(matchesSearch(headers, 'carlsen tata')).toBe(true);
    expect(matchesSearch(headers, 'carlsen open')).toBe(false);
    expect(matchesSearch(headers, '  ')).toBe(true);
  });
});

describe('showing a comment', () => {
  it('leaves out the clock and eval commands sites put in them', () => {
    expect(displayComment('[%clk 0:03:12] Good move [%eval 0.4]')).toBe('Good move');
    expect(displayComment(undefined)).toBe('');
  });
});
