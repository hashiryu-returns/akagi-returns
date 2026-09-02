// Platform metadata used by the Setup wizard and Settings page.
//
// `kind` mirrors `src/config/platform.rs::Platform` (PascalCase JSON), so
// the value flows into `AppConfig.platform.kind` unchanged.

import type { PlatformKind } from '@/types'

export type PlatformInfo = {
  kind: PlatformKind
  /** i18n key resolving to the localised platform name. */
  labelKey: string
  /**
   * Default URL for the Chromium capture backend's `start_url`. Picked so
   * the launched browser lands directly on the game's lobby/match-find page.
   */
  defaultStartUrl: string
}

/**
 * Mahjong Soul's regional web clients. Each is a separate server holding its
 * own accounts, so picking a region picks which client the launched browser
 * opens. Surfaced as a language picker rather than a URL field because that
 * is the only part a player needs to choose between.
 */
export const MAJSOUL_SERVERS = [
  { url: 'https://game.mahjongsoul.com/', labelKey: 'settings.server_jp' },
  { url: 'https://mahjongsoul.game.yo-star.com/', labelKey: 'settings.server_en' },
  { url: 'https://game.maj-soul.com/1/', labelKey: 'settings.server_cn' },
] as const

export function isKnownMajsoulServer(url: string): boolean {
  return MAJSOUL_SERVERS.some((s) => s.url === url.trim())
}

/**
 * i18n key naming the region a start URL belongs to. Falls back to the
 * generic "custom" label so a hand-edited URL still reads sensibly.
 */
export function majsoulServerLabelKey(url: string): string {
  return (
    MAJSOUL_SERVERS.find((s) => s.url === url.trim())?.labelKey ??
    'settings.server_custom'
  )
}

export const PLATFORMS: PlatformInfo[] = [
  {
    kind: 'Majsoul',
    labelKey: 'platform.majsoul',
    defaultStartUrl: MAJSOUL_SERVERS[0].url,
  },
]

const BY_KIND: Record<PlatformKind, PlatformInfo> = Object.fromEntries(
  PLATFORMS.map((p) => [p.kind, p]),
) as Record<PlatformKind, PlatformInfo>

export function platformInfo(kind: PlatformKind): PlatformInfo {
  return BY_KIND[kind]
}

/**
 * Set of every URL we have ever shipped as a "default". Used to decide
 * whether `start_url` is still a known default (so it's safe to replace)
 * or whether the user has customised it (in which case we leave it alone).
 */
const KNOWN_DEFAULT_URLS = new Set<string>([
  ...PLATFORMS.map((p) => p.defaultStartUrl),
  ...MAJSOUL_SERVERS.map((s) => s.url),
  // Shipped as a default by earlier builds that also bridged Tenhou.
  'https://tenhou.net/4/',
])

export function isKnownDefaultStartUrl(url: string): boolean {
  return KNOWN_DEFAULT_URLS.has(url.trim())
}
