// Figura corporal compartida por Skandi Fit y HABIT.
//
// Solo geometría y dibujo: ninguna referencia al estado ni al DOM de una app en
// concreto, para que las dos rendericen exactamente el mismo cuerpo. El click
// se pasa como expresión (bodyFigureSVG(view, scores, 'miHandler(event)')),
// porque cada app hace algo distinto al tocar un músculo.
//
// scoreByName es un Map de nombre de músculo -> frescura 0-100. Los nombres son
// los del motor de recuperación (Chest, Back, Quads, ...).
(function(global){
'use strict';

// Propio, no el de la app: la librería no debe depender de ningún helper del
// host. Los nombres de músculo son constantes internas, pero escaparlos deja
// que el atributo sea seguro pase lo que pase.
const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// Figura anatómica única (frente O espalda, alternables) en un viewBox de
// 240x480, ~7.5 cabezas de alto. Todo lo que va en par se dibuja SOLO del lado
// izquierdo y se espeja sobre el centro vertical con un transform al renderizar
// (ver BODY_MIRROR/bodyShapeMarkup abajo) — eso funciona con paths bezier, que
// reflejar coordenada por coordenada a mano no.
//
// Presupuesto vertical: cabeza 10-70 · cuello 70-88 · deltoide 88-148
// pecho 98-152 · abdomen 158-258 · pelvis 238-302 · muslo 292-396
// rodilla ~398 · pantorrilla 400-462 · pie 462-476
const BODY_VIEWBOX_W=240, BODY_VIEWBOX_H=480;
const P=d=>({shape:'path',d});

// The silhouette is one continuous grey body: head, neck, trunk, arms, legs. The arm's dome
// starts high (y≈90) and deliberately overlaps the torso's shoulder — the deltoid region is
// clipped to this silhouette, so any gap between torso and arm would show up as a notch in it.
const BODY_SILHOUETTE=[
  {shape:'ellipse',cx:120,cy:40,rx:25,ry:30},                                                     // head
  P('M106 60 C106 74 105 82 100 88 C108 94 132 94 140 88 C135 82 134 74 134 60 Z'),               // neck
  // trunk: traps → deltoid seam → armpit → ribs → waist (narrow) → hip
  {...P('M120 76 C112 76 102 79 94 84 C84 90 77 100 76 112 C75 124 78 133 81 143 C84 157 86 173 87 189 C88 203 88 215 89 227 C90 241 87 251 85 263 C83 277 86 291 92 301 L120 301 Z'),mirror:true},
  {...P('M80 90 C64 92 55 105 53 122 C52 140 51 160 50 178 C49 190 49 198 50 202 C58 206 68 206 74 202 C75 190 76 176 78 160 C80 142 82 120 82 106 C82 96 82 90 80 90 Z'),mirror:true},   // upper arm
  {...P('M50 204 C47 220 45 238 44 252 C43 264 45 276 49 285 C53 293 60 297 65 293 C69 289 68 280 67 271 C65 254 66 238 69 222 C70 214 71 208 72 204 C65 208 57 208 50 204 Z'),mirror:true}, // forearm + hand
  {...P('M118 288 C106 290 95 298 90 312 C85 328 84 348 85 366 C86 380 88 390 89 398 C90 412 91 428 92 442 C93 454 94 464 97 470 C104 475 112 472 113 464 C114 448 113 430 114 412 C115 396 116 380 117 364 C118 340 119 314 119 290 Z'),mirror:true} // thigh + shin + foot
];

// Shared between the two views: the deltoid cap and the upper-arm slab (biceps in front,
// triceps from behind) sit in the same place either way.
// The deltoid is kept strictly convex — an inward control point here reads as a horn once filled.
const BODY_DELTOID=P('M94 94 C84 93 71 96 64 105 C57 114 55 127 58 137 C61 146 71 148 80 144 C88 140 92 129 94 116 C95 108 95 99 94 94 Z');
const BODY_ARM_SLAB=P('M79 122 C68 126 60 137 58 151 C56 164 55 177 54 189 C61 193 69 193 75 189 C76 177 78 164 80 151 C82 139 83 129 83 122 Z');

// Regions are drawn a little "generous" and then clipped to the silhouette, so a muscle can
// bleed right to the body's edge without ever spilling outside it.
const BODY_REGIONS_FRONT=[
  {name:'Shoulders',mirror:true,...BODY_DELTOID},
  {name:'Chest',mirror:true,...P('M118 100 C107 98 96 101 90 109 C84 117 84 128 88 137 C92 146 101 150 110 150 C116 150 118 147 118 141 Z')},
  {name:'Core',mirror:true,...P('M118 158 C108 158 100 162 96 170 C93 179 93 191 94 204 C96 219 99 234 103 245 C107 254 113 258 118 258 Z')},
  {name:'Biceps',mirror:true,...BODY_ARM_SLAB},
  {name:'Forearms',mirror:true,...P('M53 210 C50 224 48 239 47 252 C46 263 48 272 51 279 C56 285 62 286 65 282 C67 277 66 269 65 261 C64 246 65 233 68 219 C63 217 57 214 53 210 Z')},
  {name:'Quads',mirror:true,...P('M117 296 C106 298 96 306 92 320 C88 334 88 351 90 366 C92 377 94 386 98 393 C105 397 112 395 115 389 C116 372 116 355 117 338 C117 322 117 308 117 296 Z')}
];
const BODY_REGIONS_BACK=[
  {name:'Shoulders',mirror:true,...BODY_DELTOID},
  // Lats: broad across the upper back, tapering into the waist — the classic V.
  {name:'Back',mirror:true,...P('M119 96 C106 96 92 102 84 113 C78 122 77 134 80 146 C84 159 91 173 99 185 C106 195 113 201 119 201 Z')},
  {name:'Triceps',mirror:true,...BODY_ARM_SLAB},
  {name:'Glutes',mirror:true,...P('M119 238 C108 238 97 244 92 254 C87 264 87 280 93 290 C99 299 110 303 119 302 Z')},
  {name:'Hamstrings',mirror:true,...P('M117 302 C106 304 96 312 92 325 C88 339 88 355 90 370 C92 380 94 388 98 394 C105 398 112 396 115 390 C116 374 116 357 117 341 C117 325 117 313 117 302 Z')},
  {name:'Calves',mirror:true,...P('M99 404 C94 411 91 421 91 433 C91 444 93 453 96 460 C104 465 111 463 113 456 C114 445 114 432 115 421 C115 413 116 407 116 402 C110 406 104 406 99 404 Z')}
];

function freshColor(score){
  const stops=[[120,139,161],[240,162,46],[29,154,108]];
  const t=Math.max(0,Math.min(100,score))/100;
  const seg=t<0.5?0:1;
  const local=t<0.5?t/0.5:(t-0.5)/0.5;
  const a=stops[seg],b=stops[seg+1];
  const mix=i=>Math.round(a[i]+(b[i]-a[i])*local);
  return `rgb(${mix(0)},${mix(1)},${mix(2)})`;
}

const BODY_MIRROR=`translate(${BODY_VIEWBOX_W},0) scale(-1,1)`;

// stroke is opt-in: the silhouette's two mirrored halves have to fuse into one continuous body
// (a stroke draws a visible seam straight down the middle of the torso), while muscle regions
// need the white outline to read as separate slabs.
function bodyShapeEl(s,fill,extraAttrs,transform,stroke){
  const attrs=`${extraAttrs||''}${transform?` transform="${transform}"`:''} fill="${fill}"${stroke?' stroke="#ffffff" stroke-width="1.6" stroke-linejoin="round"':''}`;
  return s.shape==='ellipse'
    ?`<ellipse cx="${s.cx}" cy="${s.cy}" rx="${s.rx}" ry="${s.ry}" ${attrs}/>`
    :`<path d="${s.d}" ${attrs}/>`;
}

function bodyShapeMarkup(s,fill,extraAttrs,stroke){
  return bodyShapeEl(s,fill,extraAttrs,null,stroke)
    +(s.mirror?bodyShapeEl(s,fill,extraAttrs,BODY_MIRROR,stroke):'');
}

// Every figure on the page needs its own clipPath id — Home's mini figure and Body's full one
// can be in the DOM at the same time, and a duplicated id would make one clip the other.
let bodyClipSeq=0;
function bodyFigureSVG(view,scoreByName,onclickExpr){
  const regions=view==='back'?BODY_REGIONS_BACK:BODY_REGIONS_FRONT;
  const clipId=`skandiBodyClip${++bodyClipSeq}`;
  // <clipPath> accepts shapes but not <g>, so each mirrored half carries the transform itself.
  const clip=BODY_SILHOUETTE.map(s=>{
    const half=tf=>s.shape==='ellipse'
      ?`<ellipse cx="${s.cx}" cy="${s.cy}" rx="${s.rx}" ry="${s.ry}"${tf?` transform="${tf}"`:''}/>`
      :`<path d="${s.d}"${tf?` transform="${tf}"`:''}/>`;
    return half()+(s.mirror?half(BODY_MIRROR):'');
  }).join('');
  return `<svg viewBox="0 0 ${BODY_VIEWBOX_W} ${BODY_VIEWBOX_H}" xmlns="http://www.w3.org/2000/svg" ${onclickExpr?`onclick="${onclickExpr}"`:''}>`
    +`<defs><clipPath id="${clipId}">${clip}</clipPath></defs>`
    +BODY_SILHOUETTE.map(s=>bodyShapeMarkup(s,'#d8e3ec')).join('')
    +`<g clip-path="url(#${clipId})">`
    +regions.map(r=>bodyShapeMarkup(r,freshColor(scoreByName.get(r.name)||0),` data-muscle="${esc(r.name)}" class="muscle-region"`,true)).join('')
    +`</g></svg>`;
}


const BodyFigure={
  VIEWBOX_W:BODY_VIEWBOX_W, VIEWBOX_H:BODY_VIEWBOX_H,
  SILHOUETTE:BODY_SILHOUETTE, REGIONS_FRONT:BODY_REGIONS_FRONT, REGIONS_BACK:BODY_REGIONS_BACK,
  MUSCLES:[...new Set([...BODY_REGIONS_FRONT,...BODY_REGIONS_BACK].map(r=>r.name))],
  freshColor, bodyShapeMarkup, svg:bodyFigureSVG
};

if (typeof module !== 'undefined' && module.exports) module.exports = BodyFigure;
else { global.BodyFigure = BodyFigure; global.bodyFigureSVG = bodyFigureSVG; global.freshColor = freshColor; }
})(typeof globalThis !== 'undefined' ? globalThis : this);
