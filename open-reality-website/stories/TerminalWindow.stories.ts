import type { Meta, StoryObj } from '@storybook/vue3'
import TerminalWindow from '~/components/TerminalWindow.vue'

const meta = {
  title: 'Components/TerminalWindow',
  component: TerminalWindow,
  tags: ['autodocs'],
  argTypes: {
    title: { control: 'text' },
    filename: { control: 'text' },
  },
} satisfies Meta<typeof TerminalWindow>

export default meta
type Story = StoryObj<typeof meta>

export const WithTitle: Story = {
  args: { title: 'Julia REPL' },
  render: (args) => ({
    components: { TerminalWindow },
    setup: () => ({ args }),
    template: `<TerminalWindow v-bind="args"><pre style="color:#e6e6e6">julia> println("Hello, OpenReality!")\nHello, OpenReality!</pre></TerminalWindow>`,
  }),
}

export const WithFilename: Story = {
  args: { filename: 'game.jl' },
  render: (args) => ({
    components: { TerminalWindow },
    setup: () => ({ args }),
    template: `<TerminalWindow v-bind="args"><pre style="color:#e6e6e6">using OpenReality\nrender(scene(), backend=OpenGLBackend())</pre></TerminalWindow>`,
  }),
}

export const Empty: Story = {
  render: () => ({
    components: { TerminalWindow },
    template: `<TerminalWindow><span style="color:#888">No content</span></TerminalWindow>`,
  }),
}
