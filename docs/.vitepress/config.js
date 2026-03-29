import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "Azoth",
  description: "A distributed reactive workflow engine.",
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/architecture' },
      { text: 'DSL', link: '/dsl/concepts' }
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Architecture', link: '/guide/architecture' },
          { text: 'Engine Internals', link: '/guide/internals' },
          { text: 'Implementation Plan', link: '/guide/implementation-plan' }
        ]
      },
      {
        text: 'DSL',
        items: [
          { text: 'Concepts', link: '/dsl/concepts' },
          { text: 'Operators & Functions', link: '/dsl/reference' }
        ]
      }
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/organization/azoth' }
    ]
  }
})