<script setup lang="ts">
defineProps<{
  title?: string
  filename?: string
}>()
</script>

<template>
  <div class="rounded-lg border border-or-border overflow-hidden bg-or-panel shadow-glow-green">
    <div class="flex items-center gap-2 px-4 py-2.5 bg-or-surface border-b border-or-border">
      <div class="flex gap-1.5">
        <span class="w-3 h-3 rounded-full bg-red-500/80" />
        <span class="w-3 h-3 rounded-full bg-yellow-500/80" />
        <span class="w-3 h-3 rounded-full bg-green-500/80" />
      </div>
      <span v-if="title || filename" class="text-or-text-dim text-xs font-mono ml-2">
        {{ title || filename }}
      </span>
    </div>
    <div class="p-4 overflow-x-auto">
      <slot />
    </div>
  </div>
</template>
