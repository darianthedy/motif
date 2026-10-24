import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';

/**
 * How far the on-screen keyboard covers the page. iOS lays the page out as if
 * it were not there, so a sheet pinned to the bottom would sit under it.
 */
function useKeyboardInset(): number {
  const [inset, setInset] = useState(0);
  useEffect(() => {
    const viewport = window.visualViewport;
    if (!viewport) return;
    const update = () =>
      setInset(Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop));
    update();
    viewport.addEventListener('resize', update);
    viewport.addEventListener('scroll', update);
    return () => {
      viewport.removeEventListener('resize', update);
      viewport.removeEventListener('scroll', update);
    };
  }, []);
  return inset;
}

/**
 * A panel that rises from the bottom of the screen over everything else. A
 * modal <dialog>, so focus stays in it and Escape closes it; so does a tap on
 * the dimmed page around it.
 */
export function Sheet({
  label,
  onClose,
  children,
}: {
  label: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const inset = useKeyboardInset();

  // Not closed on the way out: that fires `close`, which would call onClose
  // for a sheet already going. Leaving the page takes it out of the top layer.
  useEffect(() => {
    if (!dialog.current?.open) dialog.current?.showModal();
  }, []);

  return (
    <dialog
      ref={dialog}
      className="sheet"
      aria-label={label}
      style={{ marginBottom: inset }}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="sheet-body">{children}</div>
    </dialog>
  );
}
