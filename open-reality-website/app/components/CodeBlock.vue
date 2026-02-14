<script setup lang="ts">
import { useHighlight } from '~/composables/useHighlight'

const props = defineProps<{
  code: string
  lang?: string
  filename?: string
}>()

const highlighted = ref('')

onMounted(async () => {
  highlighted.value = await useHighlight(props.code, props.lang || 'julia')
})
</script>

<template>
  <TerminalWindow :filename="filename">
    <div
      class="font-mono text-sm leading-relaxed [&_pre]:!bg-transparent [&_code]:!bg-transparent"
      v-html="highlighted"
    />
  </TerminalWindow>
</template>
