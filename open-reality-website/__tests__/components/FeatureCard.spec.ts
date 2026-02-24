import { describe, it, expect } from 'bun:test'
import { mount } from '@vue/test-utils'
import FeatureCard from '~/components/FeatureCard.vue'

describe('FeatureCard', () => {
  it('renders title and description', () => {
    const wrapper = mount(FeatureCard, {
      props: { title: 'ECS', description: 'Entity Component System' },
    })
    expect(wrapper.find('h3').text()).toBe('ECS')
    expect(wrapper.find('p').text()).toBe('Entity Component System')
  })

  it('renders tag when provided', () => {
    const wrapper = mount(FeatureCard, {
      props: { title: 'ECS', description: 'desc', tag: 'NEW' },
    })
    const tagEl = wrapper.find('.inline-block')
    expect(tagEl.exists()).toBe(true)
    expect(tagEl.text()).toBe('NEW')
  })

  it('does not render tag element when absent', () => {
    const wrapper = mount(FeatureCard, {
      props: { title: 'ECS', description: 'desc' },
    })
    const tagEl = wrapper.find('.inline-block')
    expect(tagEl.exists()).toBe(false)
  })
})
