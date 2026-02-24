import type { Meta, StoryObj } from '@storybook/vue3'
import FeatureCard from '~/components/FeatureCard.vue'

const meta = {
  title: 'Components/FeatureCard',
  component: FeatureCard,
  tags: ['autodocs'],
  argTypes: {
    title: { control: 'text' },
    description: { control: 'text' },
    tag: { control: 'text' },
  },
} satisfies Meta<typeof FeatureCard>

export default meta
type Story = StoryObj<typeof meta>

export const WithTag: Story = {
  args: {
    title: 'ECS Architecture',
    description: 'Entity-Component-System for composable game objects with cache-friendly data layout.',
    tag: 'CORE',
  },
}

export const WithoutTag: Story = {
  args: {
    title: 'Hot Reload',
    description: 'Modify scenes and shaders live without restarting the engine.',
  },
}
