import { describe, it, expect } from 'bun:test'
import { mount } from '@vue/test-utils'
import StatBadge from '~/components/StatBadge.vue'

describe('StatBadge', () => {
  it('renders value and label from props', () => {
    const wrapper = mount(StatBadge, {
      props: { value: '938', label: 'Tests Passing' },
    })
    expect(wrapper.text()).toContain('938')
    expect(wrapper.text()).toContain('Tests Passing')
  })

  it('applies font-mono class to value element', () => {
    const wrapper = mount(StatBadge, {
      props: { value: '4', label: 'Backends' },
    })
    const valueEl = wrapper.find('.text-3xl')
    expect(valueEl.exists()).toBe(true)
    expect(valueEl.text()).toBe('4')
  })
})
