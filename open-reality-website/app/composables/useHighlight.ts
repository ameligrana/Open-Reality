import { createHighlighter, type Highlighter } from 'shiki'

let highlighterPromise: Promise<Highlighter> | null = null

function getHighlighter() {
  if (!highlighterPromise) {
    highlighterPromise = createHighlighter({
      themes: ['github-dark-default'],
      langs: ['julia', 'bash', 'toml', 'json', 'powershell'],
    })
  }
  return highlighterPromise
}

export async function useHighlight(code: string, lang: string = 'julia'): Promise<string> {
  const highlighter = await getHighlighter()
  return highlighter.codeToHtml(code, {
    lang,
    theme: 'github-dark-default',
  })
}
