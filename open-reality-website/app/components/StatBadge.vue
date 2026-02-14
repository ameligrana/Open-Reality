<script setup lang="ts">
defineProps<{
  value: string
  label: string
}>()
</script>

<template>
  <div class="text-center p-4">
    <div class="text-3xl font-mono font-bold text-or-green">{{ value }}</div>
    <div class="text-or-text-dim text-sm font-mono mt-1">{{ label }}</div>
  </div>
</template>
