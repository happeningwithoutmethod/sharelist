import { randomInt } from 'node:crypto';

/** Uppercase alphanumeric alphabet for short join codes (A–Z, 0–9). */
export const JOIN_CODE_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
export const JOIN_CODE_LENGTH = 6;

const JOIN_CODE_PATTERN = /^[A-Z0-9]{6}$/;

export function normalizeJoinCode(raw: string): string {
  return raw.trim().toUpperCase();
}

export function isJoinCode(raw: string): boolean {
  return JOIN_CODE_PATTERN.test(normalizeJoinCode(raw));
}

/** Generate a random 6-character uppercase alphanumeric code. */
export function randomJoinCode(): string {
  let code = '';
  for (let i = 0; i < JOIN_CODE_LENGTH; i++) {
    code += JOIN_CODE_ALPHABET[randomInt(JOIN_CODE_ALPHABET.length)]!;
  }
  return code;
}
