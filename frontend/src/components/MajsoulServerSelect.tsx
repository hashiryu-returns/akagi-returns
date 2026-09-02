import { useTranslation } from 'react-i18next'

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { MAJSOUL_SERVERS, isKnownMajsoulServer } from '@/lib/platforms'

/**
 * Region picker for the Chromium backend's start URL.
 *
 * The stored config value stays a URL, so a hand-edited config keeps working:
 * a value outside the shipped list is offered back as its own option rather
 * than silently replaced.
 */
export function MajsoulServerSelect({
  value,
  onChange,
}: {
  value: string
  onChange: (url: string) => void
}) {
  const { t } = useTranslation()
  const custom = value.trim() !== '' && !isKnownMajsoulServer(value)
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {MAJSOUL_SERVERS.map((s) => (
          <SelectItem key={s.url} value={s.url}>
            {t(s.labelKey)}
          </SelectItem>
        ))}
        {custom && <SelectItem value={value}>{value}</SelectItem>}
      </SelectContent>
    </Select>
  )
}
