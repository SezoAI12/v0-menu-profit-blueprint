'use client'

import React, { createContext, useContext, useState, useCallback, useEffect } from 'react'
import { translations, type Locale, type TranslationKeys } from './translations'

interface I18nContextType {
  locale: Locale
  dir: 'rtl' | 'ltr'
  t: TranslationKeys
  setLocale: (locale: Locale) => void
  toggleLocale: () => void
}

const I18nContext = createContext<I18nContextType | null>(null)

const LOCALE_COOKIE = 'menuprofit_locale'

function getStoredLocale(): Locale {
  if (typeof window === 'undefined') return 'ar'
  const stored = document.cookie
    .split('; ')
    .find((c) => c.startsWith(`${LOCALE_COOKIE}=`))
    ?.split('=')[1]
  return (stored === 'en' ? 'en' : 'ar') as Locale
}

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>('ar')
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setLocaleState(getStoredLocale())
    setMounted(true)
  }, [])

  const setLocale = useCallback((newLocale: Locale) => {
    setLocaleState(newLocale)
    document.cookie = `${LOCALE_COOKIE}=${newLocale}; path=/; max-age=${60 * 60 * 24 * 365}`
    document.documentElement.lang = newLocale
    document.documentElement.dir = newLocale === 'ar' ? 'rtl' : 'ltr'
  }, [])

  const toggleLocale = useCallback(() => {
    setLocale(locale === 'ar' ? 'en' : 'ar')
  }, [locale, setLocale])

  // Apply initial dir/lang on mount
  useEffect(() => {
    if (mounted) {
      document.documentElement.lang = locale
      document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr'
    }
  }, [locale, mounted])

  const dir = locale === 'ar' ? 'rtl' : 'ltr'
  const t = translations[locale]

  return (
    <I18nContext.Provider value={{ locale, dir, t, setLocale, toggleLocale }}>
      {children}
    </I18nContext.Provider>
  )
}

export function useI18n() {
  const context = useContext(I18nContext)
  if (!context) {
    throw new Error('useI18n must be used within an I18nProvider')
  }
  return context
}
