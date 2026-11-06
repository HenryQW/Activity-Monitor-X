import { colors } from "@henryqw/theme/tokens";
import { defineConfig } from "blume";

export default defineConfig({
  title: "Activity Monitor X",
  description:
    "Activity Monitor X records what each process on your Mac does and keeps the history, so you can see what made your Mac slow, and when.",
  feedback: false,
  footer: {
    links: [
      { label: "About Henry", href: "https://henry.wang" },
      { label: "Henry Pi Harness", href: "https://pi.henry.wang" },
      { label: "MIT License", href: "https://github.com/HenryQW/Activity-Monitor-X/blob/main/LICENSE" },
      { label: "GitHub", href: "https://github.com/HenryQW/Activity-Monitor-X" },
    ],
  },
  logo: { image: "/logo.svg", text: "AMX" },
  deployment: {
    site: "https://amx.henry.wang",
  },
  github: {
    owner: "HenryQW",
    repo: "Activity-Monitor-X",
    dir: "website",
  },
  navigation: {
    sidebar: [
      { label: "Get Started", items: ["/overview", "/install", "/how-it-works"] },
      {
        label: "Screens",
        items: ["/apps", "/inspector", "/calendar", "/alerts", "/disk", "/energy", "/hardware", "/groups", "/menu-bar", "/settings"],
      },
      { label: "Terminal", items: ["/cli"] },
      { label: "Reference", items: ["/privacy", "/glossary"] },
      { label: "Develop", items: ["/build", "/release"] },
    ],
  },
  theme: {
    accent: { dark: colors.accentSoft, light: colors.accent },
    background: { dark: colors.inverseBackground, light: colors.background },
    fonts: { body: "geist", display: "geist", mono: "geist-mono" },
    radius: "sm",
  },
});
