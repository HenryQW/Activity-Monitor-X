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
      { label: "MIT License", href: "https://github.com/HenryQW/amx/blob/main/LICENSE" },
      { label: "GitHub", href: "https://github.com/HenryQW/amx" },
    ],
  },
  logo: { image: "/icon.png", text: "AMX" },
  deployment: {
    site: "https://amx.henry.wang",
  },
  github: {
    owner: "HenryQW",
    repo: "amx",
    dir: "website",
  },
  navigation: {
    sidebar: [
      "/overview",
      "/how-it-works",
      "/install",
      "/cli",
      "/privacy",
      "/glossary",
      "/build",
      "/release",
    ],
  },
  theme: {
    accent: { dark: colors.accentSoft, light: colors.accent },
    background: { dark: colors.inverseBackground, light: colors.background },
    fonts: { body: "geist", display: "geist", mono: "geist-mono" },
    radius: "sm",
  },
});
