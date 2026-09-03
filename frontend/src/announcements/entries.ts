import type { LucideIcon } from 'lucide-react'
import { AppWindow, Gamepad2, Timer } from 'lucide-react'


/** One feature highlight inside an announcement's expanded view. */
export type AnnouncementFeature = {
  icon: LucideIcon
  /**
   * i18n leaf name: the dialog reads
   * `announcements.entries.<id>.<key>_title` and `…_desc`.
   */
  key: string
}

export type AnnouncementEntry = {
  /** Stable i18n slug: strings live under `announcements.entries.<id>`. */
  id: string
  /**
   * Publish date, ISO `YYYY-MM-DD`. Must be unique and strictly
   * descending down the array — it doubles as the "which announcements
   * has the user seen" ordering.
   */
  date: string
  /**
   * For release announcements: the exact Cargo.toml package version,
   * rendered as a badge on the row. Product news entries omit this.
   * Purely cosmetic — it does not gate visibility. Entries are bundled
   * into the build, so a client that can see an entry is already on the
   * matching release (or newer); there is nothing to hide.
   */
  version?: string
  /** Optional bundled image shown expanded; requires `<id>.image_alt`. */
  image?: string
  /** Optional external action URL; requires `<id>.link_label`. */
  link?: string
  features: AnnouncementFeature[]
}

/**
 * All in-app announcements, newest first. Add an entry (plus locale
 * strings in all four i18n resources) for every release.
 *
 * Upstream's release notes are not carried here. They described a
 * cross-platform application with an in-app updater and a companion
 * download, none of which this fork is, so keeping them would have meant
 * announcing features the build does not have.
 */
export const ANNOUNCEMENTS: AnnouncementEntry[] = [
  {
    id: 'v1_0_0',
    date: '2026-09-03',
    version: '1.0.0',
    features: [
      { icon: Gamepad2, key: 'scope' },
      { icon: Timer, key: 'timing' },
      { icon: AppWindow, key: 'profiles' },
    ],
  },
]
