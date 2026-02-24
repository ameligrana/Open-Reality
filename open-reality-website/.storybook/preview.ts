import type { Preview } from '@storybook/vue3'
import { setup } from '@storybook/vue3'
import { defineComponent, h, ref, onMounted, computed, reactive } from 'vue'

// Stub NuxtLink as a plain <a>
const NuxtLink = defineComponent({
  name: 'NuxtLink',
  props: { to: { type: [String, Object], default: '' } },
  setup(props, { slots }) {
    return () =>
      h('a', { href: typeof props.to === 'string' ? props.to : '#' }, slots.default?.())
  },
})

setup((app) => {
  app.component('NuxtLink', NuxtLink)
  app.component('NuxtRouteAnnouncer', defineComponent({ render: () => null }))

  // Provide Nuxt auto-imports as globals
  ;(globalThis as any).ref = ref
  ;(globalThis as any).onMounted = onMounted
  ;(globalThis as any).computed = computed
  ;(globalThis as any).reactive = reactive
  ;(globalThis as any).useRoute = () => ({ path: '/docs' })
  ;(globalThis as any).useSeoMeta = () => {}
  ;(globalThis as any).definePageMeta = () => {}
})

const preview: Preview = {
  parameters: {
    backgrounds: {
      default: 'dark',
      values: [{ name: 'dark', value: '#0a0f0d' }],
    },
    layout: 'centered',
  },
}

export default preview
