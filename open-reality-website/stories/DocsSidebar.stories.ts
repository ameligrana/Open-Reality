import type { Meta, StoryObj } from '@storybook/vue3'
import DocsSidebar from '~/components/DocsSidebar.vue'

const meta = {
  title: 'Components/DocsSidebar',
  component: DocsSidebar,
  tags: ['autodocs'],
  parameters: {
    layout: 'none',
  },
  decorators: [
    (story) => ({
      components: { story },
      template: '<div style="width:256px;height:100vh;background:#0d1210"><story /></div>',
    }),
  ],
} satisfies Meta<typeof DocsSidebar>

export default meta
type Story = StoryObj<typeof meta>

export const GettingStartedActive: Story = {
  render: () => ({
    components: { DocsSidebar },
    setup() {
      ;(globalThis as any).useRoute = () => ({ path: '/docs' })
      return {}
    },
    template: '<DocsSidebar />',
  }),
}

export const PhysicsActive: Story = {
  render: () => ({
    components: { DocsSidebar },
    setup() {
      ;(globalThis as any).useRoute = () => ({ path: '/docs/physics' })
      return {}
    },
    template: '<DocsSidebar />',
  }),
}
