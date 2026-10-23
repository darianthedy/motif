import { emptyLibrary, memoryBackend } from './backend';
import type { Backend, Library } from './backend';
import { neonAccount } from './neon';

export interface User {
  id: string;
  email: string;
}

/** Signing in, and the backend for whoever is signed in. */
export interface Account {
  /** Who is signed in, or null. */
  currentUser(): Promise<User | null>;
  signIn(email: string, password: string): Promise<void>;
  signUp(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  backend(user: User): Backend;
}

/**
 * Stands in for Neon when no database is configured: a dev server, the e2e
 * run. Any email and password signs in, and each account's library lives in
 * this browser's localStorage, so it survives a reload as a real one would.
 */
function devAccount(): Account {
  const USER_KEY = 'motif:dev:user';
  const libraryKey = (user: User) => `motif:dev:library:${user.id}`;

  return {
    async currentUser() {
      const stored = localStorage.getItem(USER_KEY);
      return stored ? (JSON.parse(stored) as User) : null;
    },
    async signIn(email) {
      localStorage.setItem(USER_KEY, JSON.stringify({ id: email, email }));
    },
    async signUp(email, password) {
      await this.signIn(email, password);
    },
    async signOut() {
      localStorage.removeItem(USER_KEY);
    },
    backend(user) {
      const stored = localStorage.getItem(libraryKey(user));
      const memory = memoryBackend(stored ? (JSON.parse(stored) as Library) : emptyLibrary());
      // Every write is saved as it lands; reads change nothing.
      const backend = { ...memory } as Backend;
      for (const name of Object.keys(memory) as (keyof Backend)[]) {
        if (name === 'load' || typeof memory[name] !== 'function') continue;
        const write = memory[name] as (...args: unknown[]) => Promise<unknown>;
        (backend[name] as unknown) = async (...args: unknown[]) => {
          const result = await write.apply(memory, args);
          localStorage.setItem(libraryKey(user), JSON.stringify(memory.library));
          return result;
        };
      }
      return backend;
    },
  };
}

/**
 * Neon's Data API when `VITE_NEON_BASE_URL` is set at build time, otherwise
 * the dev stand-in. The URL is not a secret: the endpoint is public by design
 * and RLS is the security boundary (see db/0001_schema.sql).
 */
const baseUrl = import.meta.env.VITE_NEON_BASE_URL as string | undefined;

export const usingDevAccount = !baseUrl;

export const account: Account = baseUrl ? neonAccount(baseUrl) : devAccount();
