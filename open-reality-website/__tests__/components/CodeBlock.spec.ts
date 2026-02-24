import { describe, it, expect, mock } from 'bun:test'
import { mount, flushPromises } from '@vue/test-utils'
import TerminalWindow from '~/components/TerminalWindow.vue'

const mockUseHighlight = mock(async (_code: string, _lang?: string) =>
  '<pre><code>highlighted code</code></pre>',
)

mock.module('~/composables/useHighlight', () => ({
  useHighlight: mockUseHighlight,
}))

// Import after mocking
const { default: CodeBlock } = await import('~/components/CodeBlock.vue')

describe('CodeBlock', () => {
  it('renders TerminalWindow as wrapper', () => {
    const wrapper = mount(CodeBlock, {
      props: { code: 'println("hi")' },
      global: { components: { TerminalWindow } },
    })
    expect(wrapper.findComponent(TerminalWindow).exists()).toBe(true)
  })

  it('passes filename to TerminalWindow', () => {
    const wrapper = mount(CodeBlock, {
      props: { code: 'x = 1', filename: 'game.jl' },
      global: { components: { TerminalWindow } },
    })
    expect(wrapper.findComponent(TerminalWindow).props('filename')).toBe('game.jl')
  })

  it('renders highlighted HTML after mount', async () => {
    const wrapper = mount(CodeBlock, {
      props: { code: 'x = 1', lang: 'julia' },
      global: { components: { TerminalWindow } },
    })
    await flushPromises()
    expect(wrapper.html()).toContain('highlighted code')
  })

  it('defaults lang to julia', async () => {
    mockUseHighlight.mockClear()
    mount(CodeBlock, {
      props: { code: 'x = 1' },
      global: { components: { TerminalWindow } },
    })
    await flushPromises()
    expect(mockUseHighlight).toHaveBeenCalledWith('x = 1', 'julia')
  })
})
