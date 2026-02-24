import type { Meta, StoryObj } from '@storybook/vue3'
import CodeBlock from '~/components/CodeBlock.vue'
import TerminalWindow from '~/components/TerminalWindow.vue'

const meta = {
  title: 'Components/CodeBlock',
  component: CodeBlock,
  tags: ['autodocs'],
  argTypes: {
    code: { control: 'text' },
    lang: { control: 'select', options: ['julia', 'bash', 'toml', 'json'] },
    filename: { control: 'text' },
  },
  decorators: [
    (story) => ({
      components: { story, TerminalWindow },
      template: '<div style="width:600px"><story /></div>',
    }),
  ],
} satisfies Meta<typeof CodeBlock>

export default meta
type Story = StoryObj<typeof meta>

export const Julia: Story = {
  args: {
    code: `using OpenReality\n\ns = scene([\n    entity([\n        transform(position=Vec3d(0,3,8)),\n        CameraComponent(fov=60.0)\n    ])\n])\nrender(s, backend=VulkanBackend())`,
    lang: 'julia',
    filename: 'game.jl',
  },
}

export const Bash: Story = {
  args: {
    code: `julia --project=. -e 'using OpenReality; run_editor()'`,
    lang: 'bash',
    filename: 'terminal',
  },
}

export const DefaultLanguage: Story = {
  args: {
    code: `x = [1, 2, 3]\nprintln(sum(x))`,
  },
}
