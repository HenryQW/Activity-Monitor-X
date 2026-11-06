import { footer } from "@henryqw/theme/projects";
import { colors } from "@henryqw/theme/tokens";
import { defineConfig } from "blume";

const site = "https://amx.henry.wang";

export default defineConfig({
  title: "Activity Monitor X",
  description:
    "Activity Monitor X records what each process on your Mac does and keeps the history, so you can see what made your Mac slow, and when.",
  feedback: false,
  footer: footer(site, "HenryQW/Activity-Monitor-X"),
  logo: { image: "/logo.svg", text: "AMX" },
  deployment: {
    site,
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
