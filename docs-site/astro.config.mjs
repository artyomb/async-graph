// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const repoUrl = 'https://github.com/artyomb/async-graph';

export default defineConfig({
	site: 'https://artyomb.github.io',
	base: '/async-graph',
	integrations: [
		starlight({
			title: 'AsyncGraph',
			description: 'Documentation for the AsyncGraph Ruby gem.',
			social: [{ icon: 'github', label: 'GitHub', href: repoUrl }],
			editLink: {
				baseUrl: `${repoUrl}/edit/main/docs-site/`,
			},
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Getting Started', slug: 'getting-started' },
						{ label: 'Example Walkthroughs', slug: 'guides/examples' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Execution Model', slug: 'guides/execution-model' },
						{ label: 'Await External Work', slug: 'guides/await' },
						{ label: 'Barrier Joins', slug: 'guides/joins' },
						{ label: 'Dynamic Goto', slug: 'guides/goto' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Runtime API', slug: 'reference/runtime-api' },
						{ label: 'Tokens and Joins', slug: 'reference/tokens-and-joins' },
					],
				},
			],
		}),
	],
});
