<script setup lang="ts">
defineProps<{
  title: string
  description: string
  tag?: string
}>()
</script>

<template>
  <div class="group p-6 rounded-lg border border-or-border bg-or-surface hover:border-or-green/50 hover:shadow-glow-green transition-all duration-300">
    <div v-if="tag" class="inline-block px-2 py-0.5 rounded text-xs font-mono font-bold text-or-green bg-or-green/10 mb-3">
      {{ tag }}
    </div>
    <h3 class="font-mono font-bold text-or-text group-hover:text-or-green transition-colors">
      {{ title }}
    </h3>
    <p class="text-or-text-dim text-sm mt-2 leading-relaxed">
      {{ description }}
    </p>
  </div>
</template>
