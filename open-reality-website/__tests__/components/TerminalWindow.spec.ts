import { describe, it, expect } from 'bun:test'
import { mount } from '@vue/test-utils'
import TerminalWindow from '~/components/TerminalWindow.vue'

describe('TerminalWindow', () => {
  it('renders three macOS-style dots', () => {
    const wrapper = mount(TerminalWindow)
    const dots = wrapper.findAll('.rounded-full')
    expect(dots).toHaveLength(3)
  })

  it('renders slot content', () => {
    const wrapper = mount(TerminalWindow, {
      slots: { default: '<p>Hello Terminal</p>' },
    })
    expect(wrapper.text()).toContain('Hello Terminal')
  })

  it('displays title when provided', () => {
    const wrapper = mount(TerminalWindow, {
      props: { title: 'my-terminal' },
    })
    expect(wrapper.text()).toContain('my-terminal')
  })

  it('displays filename when provided', () => {
    const wrapper = mount(TerminalWindow, {
      props: { filename: 'game.jl' },
    })
    expect(wrapper.text()).toContain('game.jl')
  })

  it('prefers title over filename', () => {
    const wrapper = mount(TerminalWindow, {
      props: { title: 'Title', filename: 'file.jl' },
    })
    expect(wrapper.text()).toContain('Title')
  })

  it('hides title span when neither title nor filename given', () => {
    const wrapper = mount(TerminalWindow)
    const spans = wrapper.findAll('span')
    const titleSpan = spans.find((s) => s.classes().includes('text-xs'))
    expect(titleSpan).toBeUndefined()
  })
})
