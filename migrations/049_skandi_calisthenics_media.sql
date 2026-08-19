-- Adds verified GIF media to the calisthenics exercises inserted by 048. Every URL
-- below was fetched and visually confirmed to show the matching exercise before
-- being added here. 048 already ran, so this only updates media_url/media_page_url
-- for the 20 of 34 exercises where a real, working demo GIF was found.

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/2/6/4/2/12642.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/6735-pike-push-up.html',
  updated_at = now()
where slug = 'pike-push-up';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/9/0/8/0/9080.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/4448-l-sit.html',
  updated_at = now()
where slug = 'l-sit';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/3/5/6/7/9/35679.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/2216-single-leg-squat-pistol.html',
  updated_at = now()
where slug = 'pistol-squat';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/3/3/8/8/3/33883.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/2126-muscle-up.html',
  updated_at = now()
where slug = 'muscle-up-bar';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/4/5/13145.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7190-front-lever.html',
  updated_at = now()
where slug = 'front-lever-full';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/5/1/13151.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7196-handstand.html',
  updated_at = now()
where slug = 'freestanding-handstand';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/4/9/13149.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7194-lean-planche.html',
  updated_at = now()
where slug = 'planche-lean';

update public.skandi_exercises set
  media_url = 'https://fitnessprogramer.com/wp-content/uploads/2025/04/Full-Planche.gif',
  media_page_url = 'https://fitnessprogramer.com/exercise/full-planche/',
  updated_at = now()
where slug = 'full-planche';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/4/7/13147.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7192-straddle-planche.html',
  updated_at = now()
where slug = 'straddle-planche';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/4/6/13146.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7191-back-lever.html',
  updated_at = now()
where slug = 'back-lever-full';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/4/2/13142.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7187-archer-pull-up.html',
  updated_at = now()
where slug = 'archer-pull-up';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/3/1/5/3/13153.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7198-skin-the-cat.html',
  updated_at = now()
where slug = 'skin-the-cat';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/2/1/0/5210.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/1970-handstand-push-up.html',
  updated_at = now()
where slug = 'handstand-push-up-wall';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/9/0/7/5/9075.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/4440-hollow-hold.html',
  updated_at = now()
where slug = 'hollow-body-hold';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/1/5/0/0/4/15004.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/8374-shrimp-squat.html',
  updated_at = now()
where slug = 'shrimp-squat';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/5/2/5/2/5252.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/2012-jump-squat.html',
  updated_at = now()
where slug = 'jump-squat';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/2/0/9/4/8/20948.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/7188-archer-push-up.html',
  updated_at = now()
where slug = 'archer-push-up';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/2/2/8/5/7/22857.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/12967-pseudo-planche-push-up.html',
  updated_at = now()
where slug = 'pseudo-planche-push-up';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/3/3/3/5/6/33356.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/18424-nordic-hamstring-curl-male.html',
  updated_at = now()
where slug = 'nordic-curl';

update public.skandi_exercises set
  media_url = 'https://gymvisual.com/img/p/2/0/2/9/8/20298.gif',
  media_page_url = 'https://gymvisual.com/animated-gifs/10125-leg-raise-dragon-flag.html',
  updated_at = now()
where slug = 'dragon-flag';

-- Not updated (no real, verified GIF found — left as null rather than guessed):
-- wall-handstand, frog-stand, front-lever-tuck, front-lever-advanced-tuck,
-- front-lever-straddle, one-leg-front-lever, one-arm-front-lever, back-lever-tuck,
-- back-lever-straddle, tuck-planche, advanced-tuck-planche, human-flag,
-- typewriter-pull-up, v-up
