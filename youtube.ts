export function youtubeId(input: string) {
  try {
    const u = new URL(input);
    if (u.hostname === 'youtu.be') return u.pathname.slice(1).split('/')[0];
    if (u.hostname.endsWith('youtube.com')) {
      if (u.pathname === '/watch') return u.searchParams.get('v');
      const parts = u.pathname.split('/');
      if (['embed','shorts','live'].includes(parts[1])) return parts[2];
    }
  } catch { return null; }
  return null;
}
export async function youtubeMetadata(url: string) {
  const id = youtubeId(url);
  if (!id || !/^[\w-]{11}$/.test(id)) throw new Error('올바른 YouTube URL을 입력해 주세요.');
  const res = await fetch(`https://www.youtube.com/oembed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${id}`)}&format=json`, { cache: 'no-store' });
  if (!res.ok) throw new Error('영상 정보를 가져오지 못했습니다. 공개된 YouTube 영상인지 확인해 주세요.');
  const data = await res.json();
  return { youtube_id: id, title: data.title as string, channel: data.author_name as string, thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg` };
}
