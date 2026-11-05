import './globals.css';
import type { Metadata } from 'next';
export const metadata: Metadata = { title: 'VIBE ROOM — Share your sound', description: '친구와 음악을 공유하고 서로의 취향을 발견하세요.' };
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="ko"><body>{children}</body></html>; }
