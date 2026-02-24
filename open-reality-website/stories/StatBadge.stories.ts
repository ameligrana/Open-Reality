import type { Meta, StoryObj } from '@storybook/vue3'
import StatBadge from '~/components/StatBadge.vue'

const meta = {
  title: 'Components/StatBadge',
  component: StatBadge,
  tags: ['autodocs'],
  argTypes: {
    value: { control: 'text' },
    label: { control: 'text' },
  },
} satisfies Meta<typeof StatBadge>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: { value: '938', label: 'Tests Passing' },
}

export const Backends: Story = {
  args: { value: '4', label: 'Backends' },
}

export const TextValue: Story = {
  args: { value: 'Julia', label: 'Language' },
}
