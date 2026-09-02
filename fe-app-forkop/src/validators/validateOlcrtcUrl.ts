import { ValidationResult } from './types';

export function validateOlcrtcUrl(url: string): ValidationResult {
  if (!url || typeof url !== 'string') {
    return { valid: false, message: 'URL is required' };
  }

  const trimmed = url.trim();
  if (!trimmed.startsWith('olcrtc://')) {
    return { valid: false, message: 'URL must start with olcrtc://' };
  }

  // Здесь можно добавить проверку параметров комнаты, токенов и т.д.
  try {
    const parsed = new URL(trimmed);
    if (!parsed.hostname) {
      return { valid: false, message: 'Invalid host in OlcRTC URL' };
    }
  } catch (e) {
    return { valid: false, message: 'Invalid OlcRTC URL format' };
  }

  return { valid: true, message: '' };
}
