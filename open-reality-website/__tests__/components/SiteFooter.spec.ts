import { describe, it, expect } from 'bun:test'
import { mount } from '@vue/test-utils'
import SiteFooter from '~/components/SiteFooter.vue'
import { defaultMountOptions } from '../helpers'

describe('SiteFooter', () => {
  it('renders the brand name', () => {
    const wrapper = mount(SiteFooter, defaultMountOptions)
    expect(wrapper.text()).toContain('OpenReality')
  })

  it('renders documentation links', () => {
    const wrapper = mount(SiteFooter, defaultMountOptions)
    expect(wrapper.text()).toContain('Getting Started')
    expect(wrapper.text()).toContain('Architecture')
    expect(wrapper.text()).toContain('Components')
    expect(wrapper.text()).toContain('Physics')
    expect(wrapper.text()).toContain('Rendering')
  })

  it('renders GitHub link', () => {
    const wrapper = mount(SiteFooter, defaultMountOptions)
    const ghLink = wrapper.find('a[href*="github.com"]')
    expect(ghLink.exists()).toBe(true)
  })

  it('renders the bottom tagline', () => {
    const wrapper = mount(SiteFooter, defaultMountOptions)
    expect(wrapper.text()).toContain('Built with Julia')
  })
})
