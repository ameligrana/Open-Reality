import type { StorybookConfig } from '@storybook/vue3-vite'
import { resolve } from 'path'

const config: StorybookConfig = {
  stories: ['../stories/**/*.stories.@(ts|tsx)'],
  framework: '@storybook/vue3-vite',
  addons: ['@storybook/addon-essentials', '@storybook/addon-interactions'],
  viteFinal(config) {
    config.resolve ??= {}
    config.resolve.alias ??= {}
    ;(config.resolve.alias as Record<string, string>)['~'] = resolve(
      __dirname,
      '../app',
    )
    ;(config.resolve.alias as Record<string, string>)['@'] = resolve(
      __dirname,
      '../app',
    )
    return config
  },
}

export default config
