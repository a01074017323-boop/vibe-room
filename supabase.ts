import { createBrowserClient } from '@supabase/ssr';
export function supabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error('Supabase 환경변수가 설정되지 않았습니다. .env.local을 확인해 주세요.');
  return createBrowserClient(url, key);
}
