const SEARCH_BASES = [
  'https://gymvisual.com/search?controller=search&s=',
  'https://gymvisual.com/module/iqitsearch/searchiqit?s=',
  'https://gymvisual.com/search?s=',
];

function cleanQuery(value) {
  return String(value || '')
    .replace(/[^\w\s-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
}

function absoluteUrl(url) {
  if (!url) return null;
  if (url.startsWith('//')) return `https:${url}`;
  if (url.startsWith('/')) return `https://gymvisual.com${url}`;
  return url;
}

function unique(items) {
  const seen = new Set();
  return items.filter(item => {
    const key = item.mediaUrl || item.pageUrl;
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function parseResults(html, query) {
  const results = [];
  const imgRe = /<img[^>]+(?:src|data-src|data-full-size-image-url)=["']([^"']+)["'][^>]*>/gi;
  const linkRe = /<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]{0,320}?)<\/a>/gi;
  let match;
  while ((match = imgRe.exec(html))) {
    const src = absoluteUrl(match[1]);
    if (!src || !/\.(gif|webp|jpg|jpeg|png)(\?|$)/i.test(src)) continue;
    results.push({ title: query, mediaUrl: src, pageUrl: null, source: 'Gymvisual' });
  }
  while ((match = linkRe.exec(html))) {
    const href = absoluteUrl(match[1]);
    const text = match[2].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    if (!href || !/gymvisual\.com/.test(href) || !text) continue;
    if (!/animated-gifs|exercise|gif/i.test(href + text)) continue;
    results.push({ title: text.slice(0, 90), mediaUrl: null, pageUrl: href, source: 'Gymvisual' });
  }
  return unique(results).slice(0, 8);
}

module.exports = async (req, res) => {
  const query = cleanQuery(req.query.q);
  if (!query) return res.status(400).json({ error: 'Missing query' });

  for (const base of SEARCH_BASES) {
    try {
      const response = await fetch(`${base}${encodeURIComponent(query)}`, {
        headers: {
          'user-agent': 'SkandiFitBot/1.0 (+https://habittraininghub.app/skandi)',
          accept: 'text/html,application/json',
        },
      });
      const text = await response.text();
      let results = [];
      try {
        const json = JSON.parse(text);
        const raw = Array.isArray(json) ? json : Object.values(json).flat();
        results = raw.map(item => ({
          title: item.name || item.title || query,
          mediaUrl: absoluteUrl(item.image || item.cover || item.img || item.media_url),
          pageUrl: absoluteUrl(item.url || item.link),
          source: 'Gymvisual',
        }));
      } catch {
        results = parseResults(text, query);
      }
      results = unique(results).slice(0, 8);
      if (results.length) return res.status(200).json({ query, results });
    } catch {
      // Try the next known Gymvisual route.
    }
  }

  return res.status(200).json({ query, results: [] });
};
