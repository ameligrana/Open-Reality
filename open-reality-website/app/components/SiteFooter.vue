<template>
  <footer class="border-t border-or-border bg-or-bg py-12 mt-24">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
        <div>
          <span class="text-or-green font-mono font-bold">&gt;_ OpenReality</span>
          <p class="text-or-text-dim text-sm mt-2">
            Declarative code-first game engine built in Julia.
          </p>
        </div>

        <div>
          <h4 class="font-mono text-or-text text-sm font-bold mb-3">Documentation</h4>
          <div class="space-y-1.5">
            <NuxtLink to="/docs" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">Getting Started</NuxtLink>
            <NuxtLink to="/docs/architecture" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">Architecture</NuxtLink>
            <NuxtLink to="/docs/components" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">Components</NuxtLink>
            <NuxtLink to="/docs/physics" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">Physics</NuxtLink>
            <NuxtLink to="/docs/rendering" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">Rendering</NuxtLink>
          </div>
        </div>

        <div>
          <h4 class="font-mono text-or-text text-sm font-bold mb-3">Community</h4>
          <div class="space-y-1.5">
            <a href="https://github.com/sinisterMage/Open-Reality" target="_blank" class="block text-or-text-dim text-sm hover:text-or-green transition-colors">GitHub</a>
          </div>
        </div>
      </div>

      <div class="mt-8 pt-8 border-t border-or-border text-center text-or-text-dim text-xs font-mono">
        Built with Julia. Rendered with OpenReality.
      </div>
    </div>
  </footer>
</template>
