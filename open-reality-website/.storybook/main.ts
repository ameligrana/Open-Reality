import type { StorybookConfig } from '@storybook/vue3-vite'
import { resolve } from 'path'

const config: StorybookConfig = {
  stories: ['../stories/**/*.stories.@(ts|tsx)'],
  framework: '@storybook/vue3-vite',
  addons: ['@storybook/addon-essentials', '@storybook/addon-interactions'],
  async viteFinal(config) {
    const vue = (await import('@vitejs/plugin-vue')).default
    config.plugins ??= []
    config.plugins.push(vue())

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
