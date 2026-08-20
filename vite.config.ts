import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// Relative asset paths, so the build runs from any directory without being
// rebuilt for it: github.io/<repo>/, a local `file://` open, or a domain root.
// Safe while there is no client-side routing; nested routes would need a hash
// router or a build-time absolute base.
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      // A daily habit app, so a stale shell is worse than a reload: take the
      // new service worker immediately rather than waiting for tabs to close.
      registerType: 'autoUpdate',
      manifest: {
        name: 'Chesslingo',
        short_name: 'Chesslingo',
        description: 'Continuous chess puzzle sessions over your own collections.',
        theme_color: '#16171d',
        background_color: '#16171d',
        display: 'standalone',
        orientation: 'portrait',
        // Relative, to match the base path and stay installable from a subpath
        // such as /chesslingo/.
        start_url: '.',
        scope: '.',
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest}'],
        // Everything is client-side, so any navigation resolves to the shell.
        navigateFallback: 'index.html',
      },
    }),
  ],
});
