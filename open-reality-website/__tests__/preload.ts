import { plugin } from 'bun'
import { GlobalRegistrator } from '@happy-dom/global-registrator'

// Register DOM globals (window, document, etc.) for @vue/test-utils
GlobalRegistrator.register()

// Vue SFC (.vue) loader plugin
plugin({
  name: 'vue-sfc',
  async setup(build) {
    const { parse, compileScript, compileTemplate } =
      await import('@vue/compiler-sfc')

    build.onLoad({ filter: /\.vue$/ }, async (args) => {
      const source = await Bun.file(args.path).text()
      const filename = args.path
      const id = filename

      const { descriptor, errors } = parse(source, { filename })
      if (errors.length) {
        throw new Error(
          `Vue SFC parse errors in ${filename}: ${errors.map((e) => e.message).join(', ')}`,
        )
      }

      let scriptCode = ''
      let bindings: Record<string, any> = {}

      if (descriptor.script || descriptor.scriptSetup) {
        const compiled = compileScript(descriptor, { id, sourceMap: false })
        // The compiled content has `export default` — replace it with a variable assignment.
        // compileScript for <script setup> outputs: `export default /*@__PURE__*/_defineComponent({ ... })`
        scriptCode = compiled.content.replace(
          /export\s+default\s+/,
          'const __sfc_main = ',
        )
        bindings = compiled.bindings || {}
      } else {
        scriptCode = 'const __sfc_main: Record<string, any> = {}'
      }

      let renderCode = ''
      if (descriptor.template) {
        const compiled = compileTemplate({
          source: descriptor.template.content,
          filename,
          id,
          compilerOptions: { bindingMetadata: bindings },
        })
        renderCode = compiled.code
      }

      const code = [
        scriptCode,
        renderCode,
        `__sfc_main.render = render`,
        `__sfc_main.__file = ${JSON.stringify(filename)}`,
        `export default __sfc_main`,
      ].join('\n')

      return { contents: code, loader: 'ts' }
    })
  },
})

// CSS/SCSS mock — return empty object for style imports
plugin({
  name: 'css-mock',
  setup(build) {
    build.onLoad({ filter: /\.(css|less|scss)$/ }, () => {
      return { contents: 'export default {}', loader: 'js' }
    })
  },
})
