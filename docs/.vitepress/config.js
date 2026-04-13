import { withMermaid } from 'vitepress-plugin-mermaid'

export default withMermaid({
  title: "Azoth",
  description: "A distributed reactive workflow engine.",
  mermaid: {
    theme: 'base',
    themeVariables: {
      primaryColor: '#8B5CF6',
      primaryTextColor: '#E2E8F0',
      primaryBorderColor: '#7C3AED',
      lineColor: '#94A3B8',
      secondaryColor: '#334155',
      tertiaryColor: '#1E293B',
      background: '#0F172A',
      mainBkg: '#1E293B',
      nodeBorder: '#334155',
      clusterBkg: '#1E293B',
      titleColor: '#E2E8F0',
      edgeLabelBackground: '#334155',
      attributeBackgroundColorEven: '#1E293B',
      attributeBackgroundColorOdd: '#0F172A',
      fontFamily: 'Lexend, sans-serif',
    }
  },
  mermaidPlugin: {
    class: 'mermaid'
  },
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
          { text: 'Implementation Plan', link: '/guide/implementation-plan' },
          { text: 'Color Scheme', link: '/guide/color-scheme' }
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