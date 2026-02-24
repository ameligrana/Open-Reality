import { ref, onMounted, computed, reactive } from 'vue'
import { config } from '@vue/test-utils'
import NuxtLinkStub from './stubs/NuxtLink'

// Nuxt auto-imports — provide as globals for <script setup> components
;(globalThis as any).ref = ref
;(globalThis as any).onMounted = onMounted
;(globalThis as any).computed = computed
;(globalThis as any).reactive = reactive
;(globalThis as any).useRoute = () => ({ path: '/' })
;(globalThis as any).useSeoMeta = () => {}
;(globalThis as any).definePageMeta = () => {}

// Register global component stubs (Nuxt auto-imports all components in app/components/)
config.global.stubs = {
  NuxtLink: NuxtLinkStub as any,
  NuxtRouteAnnouncer: true,
}
