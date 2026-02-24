import { describe, it, expect, mock } from 'bun:test'
import { mount } from '@vue/test-utils'
import TerminalWindow from '~/components/TerminalWindow.vue'
import { defaultMountOptions } from '../helpers'

mock.module('~/composables/useHighlight', () => ({
  useHighlight: mock(async () => '<pre><code>mocked</code></pre>'),
}))

const { default: CodeBlock } = await import('~/components/CodeBlock.vue')
const { default: HeroSection } = await import('~/components/HeroSection.vue')

const mountOptions = {
  global: {
    ...defaultMountOptions.global,
    components: { CodeBlock, TerminalWindow },
  },
}

describe('HeroSection', () => {
  it('renders the heading', () => {
    const wrapper = mount(HeroSection, mountOptions)
    expect(wrapper.text()).toContain('Open')
    expect(wrapper.text()).toContain('Reality')
  })

  it('renders the tagline', () => {
    const wrapper = mount(HeroSection, mountOptions)
    expect(wrapper.text()).toContain('declarative, code-first game engine')
  })

  it('renders Get Started link', () => {
    const wrapper = mount(HeroSection, mountOptions)
    expect(wrapper.text()).toContain('Get Started')
  })

  it('renders View Source GitHub link', () => {
    const wrapper = mount(HeroSection, mountOptions)
    const ghLink = wrapper.find('a[href*="github.com"]')
    expect(ghLink.exists()).toBe(true)
  })

  it('renders version badge', () => {
    const wrapper = mount(HeroSection, mountOptions)
    expect(wrapper.text()).toContain('938 tests passing')
  })
})
