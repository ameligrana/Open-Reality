import type { Meta, StoryObj } from '@storybook/vue3'
import HeroSection from '~/components/HeroSection.vue'
import CodeBlock from '~/components/CodeBlock.vue'
import TerminalWindow from '~/components/TerminalWindow.vue'

const meta = {
  title: 'Sections/HeroSection',
  component: HeroSection,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
  decorators: [
    (story) => ({
      components: { story, CodeBlock, TerminalWindow },
      template: '<div style="background:#0a0f0d"><story /></div>',
    }),
  ],
} satisfies Meta<typeof HeroSection>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
