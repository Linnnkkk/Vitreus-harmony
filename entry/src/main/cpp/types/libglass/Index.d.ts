export const vtGlassRegister: (id: string) => void;
export const vtGlassUnregister: (id: string) => void;
export const vtGlassSetParams: (id: string, intensity: number, waveSpeed: number) => void;
export const vtGlassStart: (id: string) => void;
export const vtGlassStop: (id: string) => void;
export const vtGlassTouch: (id: string, x: number, y: number) => void;
export const vtGlassRipple: (id: string, x: number, y: number, force: number) => void;
