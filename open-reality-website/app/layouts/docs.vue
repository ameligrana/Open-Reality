<template>
  <div class="min-h-screen flex flex-col bg-or-bg">
    <NavBar />
    <div class="flex-1 flex">
      <DocsSidebar />
      <main class="flex-1 max-w-4xl px-6 sm:px-8 py-12">
        <slot />
      </main>
    </div>
    <SiteFooter />
  </div>
</template>
