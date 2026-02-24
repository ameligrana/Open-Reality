import { describe, it, expect } from 'bun:test'
import { mount } from '@vue/test-utils'
import NavBar from '~/components/NavBar.vue'
import { defaultMountOptions } from '../helpers'

describe('NavBar', () => {
  it('renders the brand text', () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    expect(wrapper.text()).toContain('OpenReality')
  })

  it('renders navigation links', () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    expect(wrapper.text()).toContain('Features')
    expect(wrapper.text()).toContain('Examples')
    expect(wrapper.text()).toContain('Docs')
  })

  it('renders GitHub external link', () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    const ghLink = wrapper.find('a[href*="github.com"]')
    expect(ghLink.exists()).toBe(true)
    expect(ghLink.attributes('target')).toBe('_blank')
  })

  it('mobile menu is hidden by default', () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    const mobileMenu = wrapper.find('.pb-4.space-y-2')
    expect(mobileMenu.exists()).toBe(false)
  })

  it('toggles mobile menu on button click', async () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    await wrapper.find('button').trigger('click')
    const mobileMenu = wrapper.find('.pb-4.space-y-2')
    expect(mobileMenu.exists()).toBe(true)
  })

  it('closes mobile menu when a mobile link is clicked', async () => {
    const wrapper = mount(NavBar, defaultMountOptions)
    await wrapper.find('button').trigger('click')
    const mobileLinks = wrapper.findAll('.pb-4 a')
    expect(mobileLinks.length).toBeGreaterThan(0)
    await mobileLinks[0].trigger('click')
    await wrapper.vm.$nextTick()
    const mobileMenu = wrapper.find('.pb-4.space-y-2')
    expect(mobileMenu.exists()).toBe(false)
  })
})
