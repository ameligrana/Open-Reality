<template>
  <div class="min-h-screen flex flex-col bg-or-bg">
    <NavBar />
    <main class="flex-1">
      <slot />
    </main>
    <SiteFooter />
  </div>
</template>
