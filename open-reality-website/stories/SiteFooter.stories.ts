import type { Meta, StoryObj } from '@storybook/vue3'
import SiteFooter from '~/components/SiteFooter.vue'

const meta = {
  title: 'Sections/SiteFooter',
  component: SiteFooter,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
  decorators: [
    (story) => ({
      components: { story },
      template: '<div style="background:#0a0f0d"><story /></div>',
    }),
  ],
} satisfies Meta<typeof SiteFooter>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
