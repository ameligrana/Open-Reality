import type { Config } from 'tailwindcss'

export default {
  content: [],
  theme: {
    extend: {
      colors: {
        'or-bg': '#0a0e14',
        'or-surface': '#0d1117',
        'or-panel': '#161b22',
        'or-border': '#21262d',
        'or-green': '#00ff9f',
        'or-cyan': '#22d3ee',
        'or-amber': '#f59e0b',
        'or-text': '#e6edf3',
        'or-text-dim': '#8b949e',
        'or-text-code': '#c9d1d9',
      },
      fontFamily: {
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        'glow-green': '0 0 20px rgba(0, 255, 159, 0.15)',
        'glow-cyan': '0 0 20px rgba(34, 211, 238, 0.15)',
      },
      animation: {
        'pulse-glow': 'pulse-glow 2s ease-in-out infinite',
        'blink': 'blink 1s step-end infinite',
      },
      keyframes: {
        'pulse-glow': {
          '0%, 100%': { boxShadow: '0 0 20px rgba(0, 255, 159, 0.1)' },
          '50%': { boxShadow: '0 0 40px rgba(0, 255, 159, 0.25)' },
        },
        'blink': {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0' },
        },
      },
    },
  },
  plugins: [],
} satisfies Config
