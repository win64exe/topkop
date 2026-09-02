import { ValidationResult } from './types';

export function validateWdttUrl(url: string): ValidationResult {
  if (!url || typeof url !== 'string') {
    return { valid: false, message: 'URL is required' };
  }

  const trimmed = url.trim();
  if (!trimmed.startsWith('wdtt://')) {
    return { valid: false, message: 'URL must start with wdtt://' };
  }

  // Здесь можно добавить более строгую проверку формата (host, port, параметры)
  // согласно спецификации WDTT.
  try {
    // Временная проверка через URL API, если формат близок к стандартному
    const parsed = new URL(trimmed);
    if (!parsed.hostname) {
      return { valid: false, message: 'Invalid host in WDTT URL' };
    }
  } catch (e) {
    return { valid: false, message: 'Invalid WDTT URL format' };
  }

  return { valid: true, message: '' };
}
