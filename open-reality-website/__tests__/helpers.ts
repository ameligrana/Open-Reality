import NuxtLinkStub from './stubs/NuxtLink'

export const defaultMountOptions = {
  global: {
    stubs: {
      NuxtLink: NuxtLinkStub as any,
      NuxtRouteAnnouncer: true,
    },
  },
}
