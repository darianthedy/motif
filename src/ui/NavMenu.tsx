export type Section = 'puzzles' | 'account';

const SECTIONS: { id: Section; label: string }[] = [
  { id: 'puzzles', label: 'Puzzles' },
  { id: 'account', label: 'Account' },
];

interface Props {
  section: Section;
  onSelect: (section: Section) => void;
}

/**
 * The bar along the bottom, within reach of a thumb on an installed PWA. Only
 * shown on a section's front page: deeper screens have their own way back, and
 * a session needs the room for the board.
 */
export function NavMenu({ section, onSelect }: Props) {
  return (
    <nav className="nav-menu" aria-label="Sections">
      {SECTIONS.map(({ id, label }) => (
        <button
          key={id}
          type="button"
          aria-current={id === section ? 'page' : undefined}
          onClick={() => onSelect(id)}
        >
          {label}
        </button>
      ))}
    </nav>
  );
}
