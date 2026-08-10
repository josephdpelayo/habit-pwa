-- Attach real technique GIFs to the original 12 Skandi Fit exercises (seeded in 040/041
-- without media). GIFs are curated matches from Gymvisual's free catalog, only applied
-- where media_url is still empty so any manually-curated media is left untouched.

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/7/5/5/2/17552.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1519-barbell-bench-press.html',
  updated_at = now()
where slug = 'barbell-bench-press' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/0/2/2/5022.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1782-dumbbell-bench-press.html',
  updated_at = now()
where slug = 'dumbbell-bench-press' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/4/7/7/4/4774.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1537-barbell-full-squat.html',
  updated_at = now()
where slug = 'barbell-squat' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/2/8/5/3/2/28532.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1579-barbell-romanian-deadlift.html',
  updated_at = now()
where slug = 'romanian-deadlift' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/6/6/9/0/6690.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/3202-wide-grip-pull-up.html',
  updated_at = now()
where slug = 'wide-grip-pull-ups' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/6/5/9/2/6592.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/3098-chin-up.html',
  updated_at = now()
where slug = 'supinated-pull-ups' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/3/4/4/5344.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/2103-lever-t-bar-row-plate-loaded.html',
  updated_at = now()
where slug = 't-bar-row' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/8/5/8/5858.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/2617-barbell-standing-military-press.html',
  updated_at = now()
where slug = 'shoulder-press' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/4/9/8/4/4984.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1744-chest-dip.html',
  updated_at = now()
where slug = 'dips' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/0/2/7/5027.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1787-dumbbell-biceps-curl.html',
  updated_at = now()
where slug = 'dumbbell-curl' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/4/9/3/3/4933.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1693-cable-pushdown-with-rope-attachment.html',
  updated_at = now()
where slug = 'rope-triceps-extension' and media_url is null;

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/9/0/3/8/9038.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/4402-front-plank.html',
  updated_at = now()
where slug = 'plank' and media_url is null;
