// Cambiar, agregar y cerrar un entreno (bloque 1): orden de parecidos, recientes,
// qué se guarda en la rutina y qué marca "Hice todo lo planeado". Corre las
// funciones de app.html tal cual, con Supabase y el DOM simulados.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const app=fs.readFileSync(require('node:path').join(__dirname,'../app.html'),'utf8');
function source(a,b){const start=app.indexOf(a),end=app.indexOf(b,start);assert.ok(start>=0&&end>start,'no encontré '+a);return app.slice(start,end);}

const catalog=[
  {id:'c-bench',slug:'bench-press-barra',name:'Bench press barra',category:'Fuerza',primary_muscle:'Pecho',secondary_muscles:['Tríceps','Hombros'],equipment:['Barra','Banco'],movement_pattern:'Empuje horizontal',muscle_split:{Chest:60,Triceps:25,Shoulders:15}},
  {id:'c-db',slug:'bench-press-mancuernas',name:'Bench press mancuernas',category:'Fuerza',primary_muscle:'Pecho',secondary_muscles:['Tríceps','Hombros'],equipment:['Mancuernas','Banco'],movement_pattern:'Empuje horizontal',muscle_split:{Chest:60,Triceps:20,Shoulders:20}},
  {id:'c-dips',slug:'fondos-en-paralelas',name:'Fondos en paralelas',category:'Calistenia',primary_muscle:'Tríceps',secondary_muscles:['Pecho','Hombros'],equipment:['Peso corporal','Paralelas'],movement_pattern:'Empuje vertical',muscle_split:{Triceps:50,Chest:35,Shoulders:15}},
  {id:'c-push',slug:'push-up',name:'Push up',category:'Calistenia',primary_muscle:'Pecho',secondary_muscles:['Tríceps','Hombros','Core'],equipment:['Peso corporal'],movement_pattern:'Empuje horizontal',aliases:['lagartija'],muscle_split:{Chest:55,Triceps:25,Shoulders:10,Core:10}},
  {id:'c-curl',slug:'curl-biceps-mancuernas',name:'Curl bíceps mancuernas',category:'Fuerza',primary_muscle:'Bíceps',secondary_muscles:['Antebrazo'],equipment:['Mancuernas'],movement_pattern:'Flexión codo',muscle_split:{Biceps:85,Forearms:15}},
  {id:'c-squat',slug:'sentadilla-barra',name:'Sentadilla barra',category:'Fuerza',primary_muscle:'Cuádriceps',secondary_muscles:['Glúteos'],equipment:['Barra'],movement_pattern:'Sentadilla',muscle_split:{Quads:60,Glutes:30,Core:10}},
  {id:'c-ext',slug:'extension-triceps-cuerda',name:'Extensión tríceps cuerda',category:'Fuerza',primary_muscle:'Tríceps',secondary_muscles:[],equipment:['Polea'],movement_pattern:'Extensión codo',muscle_split:{Triceps:100}}
];

const h=new Function('catalog',`
  let activeCoachingSession=null, coachSessionSets={}, coachBoardsById={}, wsSwapTarget=null, wsSwapQuery='', wsAddOpen=false, wsAddQuery='';
  const sbUser={id:'me'}, window={}, MEMBER_ROUTINE_COLOR='#a78bfa';
  let HabitTraining=null;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const exerciseCatalogRows=()=>catalog;
  const exerciseWeightUnit=()=>'kg', lbToKg=x=>x/2.2046, getSetRowElement=()=>null;
  const MUSCLE_ES_TO_EN={'Pecho':'Chest','Espalda':'Back','Hombros':'Shoulders','Bíceps':'Biceps','Tríceps':'Triceps','Antebrazo':'Forearms','Core':'Core','Glúteos':'Glutes','Cuádriceps':'Quads','Femorales':'Hamstrings','Pantorrillas':'Calves'};
  const LEGACY_MUSCLE_SPLIT={};
  const logged=[], updates=[];
  const logSetToUserScores=row=>logged.push(row);
  let failIds=new Set();
  async function trainingUpdate(table,id,patch,current){
    updates.push({table,id,patch});
    if(failIds.has(id))throw new Error('red');
    return Object.assign({},current,patch);
  }
  const crypto={randomUUID:()=>'uuid-new'};
  const videoKindRank=()=>0;
  ${source('function exerciseSlug(', 'function normalizeExerciseCatalogRow(')}
  ${source('const EXERCISE_SIG_STOPWORDS', 'function applyExerciseCatalogPick(')}
  ${source('function parsePyramidReps(', 'function exercisePyramidSteps(')}
  ${source('function parseTargetRir(', 'function exerciseMuscleLabel(')}
  ${source('function sessionExerciseList(', 'function buildTrainingExerciseSnapshot(')}
  ${source('function findExerciseByExKey(', 'function isSetPending(')}
  ${source('function defaultRepsFromTarget(', 'async function toggleSetDoneSb(')}
  ${source('function exerciseMuscleSplit(', '// Series completadas de los últimos días')}
  ${source('function wsSessionChanges(', 'async function wsOfferSaveSessionChanges(')}
  ${source('async function wsMarkPendingAsPlannedSb(', '// ── Entrenos que se quedaron abiertos')}
  ${source('function wsNorm(', '// ── Recientes')}
  let wsRecents=null;
  ${source('function wsRecentFor(', 'function wsToggleSwap(')}
  ${source('function wsSwapListHtml(', 'function wsRenderSwapList(')}
  ${source('function wsAddListHtml(', 'function wsRenderAddList(')}
  return {
    setSession(row,sets,board){activeCoachingSession=row;coachSessionSets=sets||{};if(board)coachBoardsById[board.id]=board;},
    setRecents(r){wsRecents=r;},
    swapList(exKey,q=''){wsSwapTarget=exKey;wsSwapQuery=q;return wsSwapListHtml();},
    addList(q=''){wsAddQuery=q;return wsAddListHtml();},
    similarity:(a,b)=>wsSimilarity(a,b),
    rowFor:ex=>wsCatalogRowFor(ex),
    changes:(row,sets)=>wsSessionChanges(row,sets),
    toRoutine:ex=>wsRoutineExerciseFromSession(ex),
    markPlanned:at=>wsMarkPendingAsPlannedSb(at),
    sets:()=>coachSessionSets, logged, updates, failIds,
    setHabitTraining(x){window.HabitTraining=x;HabitTraining=x;}
  };
`)(catalog);

const names=html=>[...html.matchAll(/class="ws-pick-txt">(?:<span class="ws-pick-mark">[^<]*<\/span>)?([^<]+)</g)].map(m=>m[1]);

// ── Parecidos ─────────────────────────────────────────────────────────────
const board={id:'b1',name:'Empuje',owner_id:'me',exercises:[
  {id:'e1',name:'Bench press barra',catalogId:'c-bench',exerciseKey:'bench-press-barra',sets:'3',reps:'8-10',rest:'2 min'},
  {id:'e2',name:'Extensión tríceps cuerda',catalogId:'c-ext',sets:'3',reps:'12'},
  {id:'e3',name:'Aguante de 90 grados',muscleGroup:'Hombros',secondaryMuscleGroups:['Tríceps','Pecho'],movementPattern:'Empuje vertical',equipment:['Peso corporal'],sets:'2',reps:'fallo'}
]};
const row={id:'s1',board_id:'b1',exercise_snapshot:[],session_exercises:[]};
h.setSession(row,{},board);
const swapBench=names(h.swapList('e1'));
assert.equal(swapBench[0],'Bench press mancuernas','al cambiar banca, primero el otro press de pecho');
assert.ok(swapBench.includes('Push up')&&swapBench.includes('Fondos en paralelas'));
assert.ok(!swapBench.includes('Sentadilla barra'),'una sentadilla no se parece a una banca');
assert.ok(!swapBench.includes('Extensión tríceps cuerda'),'lo que ya está en la sesión no se ofrece');
assert.ok(!swapBench.includes('Bench press barra'),'ni el propio ejercicio');
assert.ok(h.similarity(catalog[0],catalog[1])>h.similarity(catalog[0],catalog[4]));
// Un ejercicio escrito a mano, sin ficha, se compara con lo que trae escrito.
const swap90=names(h.swapList('e3'));
assert.ok(swap90.length>0&&swap90.includes('Fondos en paralelas'),'sin ficha también hay parecidos');
assert.ok(!swap90.includes('Sentadilla barra'));
// Escribiendo: todo el catálogo que coincida, sin acentos de por medio.
assert.deepEqual(names(h.swapList('e1','curl biceps')),['Curl bíceps mancuernas']);
assert.deepEqual(names(h.swapList('e1','lagartija')),['Push up'],'busca también en los alias');

// ── Recientes al agregar ──────────────────────────────────────────────────
h.setRecents(null);
assert.match(h.addList(),/Buscando tus recientes/);
h.setRecents([
  {row:catalog[4],sets:3,reps:'10',rest:'60s',targetRir:null,weight:12.5,actualReps:10,seconds:null},
  {row:catalog[0],sets:4,reps:'6',rest:'2 min',targetRir:2,weight:80,actualReps:6,seconds:null},
  {row:catalog[3],sets:2,reps:'max',rest:'',targetRir:null,weight:null,actualReps:25,seconds:null}
]);
const recentHtml=h.addList();
assert.deepEqual(names(recentHtml),['Curl bíceps mancuernas','Push up'],'lo que ya está en la sesión no sale en recientes');
assert.match(recentHtml,/3×10 · 12\.5 kg/);
assert.match(recentHtml,/2×25</);
assert.equal(names(h.addList('press'))[0],'Bench press mancuernas','buscando: el que ya está en la sesión no se ofrece');
// Lo reciente desempata entre parecidos pero no vuelve parecido lo que no lo es.
assert.ok(!names(h.swapList('e1')).includes('Curl bíceps mancuernas'),'un curl reciente no sustituye a la banca');
assert.equal(names(h.addList('mancuernas'))[0],'Curl bíceps mancuernas','buscando: tus recientes primero');
assert.equal(h.rowFor({_exKey:'cat-push-up#2',name:'x'}).id,'c-push','un agregado en vivo se reconoce por su ex_key');

// ── Qué se guarda en la rutina ────────────────────────────────────────────
const snapshot=board.exercises.map(e=>({...e,_exKey:e.id,metricType:'reps',snapshotIndex:0}));
const changed={id:'s2',board_id:'b1',exercise_snapshot:snapshot,session_exercises:[
  {name:'Bench press mancuernas',catalogId:'c-db',sets:'3',reps:'8-10',rest:'2 min',ex_key:'cat-bench-press-mancuernas',replaces:'e1'},
  {replaces:'e3',removed:true},
  {name:'Curl bíceps mancuernas',catalogId:'c-curl',sets:'3',reps:'10',ex_key:'cat-curl-biceps-mancuernas'}
]};
// Con una serie de banca ya hecha antes del cambio: esa queda en la hoja como
// "cambiado a media sesión", pero no pasa a la rutina.
const setsDone={e1:[{set_idx:0,done:true}],'cat-bench-press-mancuernas':[{set_idx:0,done:true}]};
const c=h.changes(changed,setsDone);
assert.deepEqual({swapped:c.swapped,added:c.added,removed:c.removed},{swapped:1,added:1,removed:1});
const saved=c.finalList.map(h.toRoutine);
assert.deepEqual(saved.map(e=>e.name),['Bench press mancuernas','Extensión tríceps cuerda','Curl bíceps mancuernas']);
assert.deepEqual(saved.map(e=>e.id),['cat-bench-press-mancuernas','e2','cat-curl-biceps-mancuernas'],'el id es la clave de hoy: la próxima vez encuentra estas series');
assert.equal(saved[0].exerciseKey,'bench-press-mancuernas');
assert.equal(saved[0].muscleGroup,'Pecho');
assert.ok(saved.every(e=>!('_exKey' in e)&&!('replaces' in e)&&!('ex_key' in e)&&!('snapshotIndex' in e)));
assert.equal(h.changes({...changed,session_exercises:[]},{}),null,'sin cambios no se pregunta nada');
// Cambiar dos veces seguidas el mismo hueco cuenta como un cambio.
const twice={...changed,session_exercises:[
  {name:'Bench press mancuernas',catalogId:'c-db',ex_key:'cat-bench-press-mancuernas',replaces:'e1'},
  {name:'Push up',catalogId:'c-push',ex_key:'cat-push-up',replaces:'cat-bench-press-mancuernas'}]};
const c2=h.changes(twice,{});
assert.deepEqual({swapped:c2.swapped,added:c2.added,removed:c2.removed},{swapped:1,added:0,removed:0});
assert.equal(c2.finalList[0].name,'Push up');

// En un entreno libre, cambiar un ejercicio agregado lo reemplaza (antes se quedaba igual).
const freeSwap={id:'s9',board_id:null,exercise_snapshot:[],session_exercises:[
  {name:'Dominadas',catalogId:'c-pull',ex_key:'cat-dominadas'},
  {name:'Remo',catalogId:'c-row',ex_key:'cat-remo',replaces:'cat-dominadas'},
  {name:'Fondos',catalogId:'c-dip',ex_key:'cat-fondos'},
  {replaces:'cat-fondos',removed:true}]};
const c3=h.changes(freeSwap,{});
assert.deepEqual(c3.finalList.map(e=>e.name),['Remo'],'el agregado cambiado se ve como el nuevo, y el quitado no se ve');

// ── Hice todo lo planeado ─────────────────────────────────────────────────
h.setHabitTraining({metricType:ex=>/s$|:/.test(String(ex.reps))?'time':'reps',parseSeconds:t=>{const m=String(t).match(/^(\d+)s$/);return m?+m[1]:null;}});
const live={id:'s3',board_id:'b2',exercise_snapshot:[],session_exercises:[]};
const board2={id:'b2',name:'Tirón',owner_id:'me',exercises:[
  {id:'p1',name:'Dominadas',sets:'2',reps:'6-8'},
  {id:'p2',name:'Aguante front lever',sets:'1',reps:'30s'},
  {id:'p3',name:'Front press',sets:'1',reps:'fallo'},
  {id:'p4',name:'Remo',sets:'2',reps:'10'}]};
h.setSession(live,{
  p1:[{id:'a',ex_key:'p1',set_idx:0,done:true,actual_reps:8,reps_target:'6-8'},{id:'b',ex_key:'p1',set_idx:1,done:false,reps_target:'6-8'}],
  p2:[{id:'c',ex_key:'p2',set_idx:0,done:false,reps_target:'30s'}],
  p3:[{id:'d',ex_key:'p3',set_idx:0,done:false,reps_target:'fallo'}],
  p4:[{id:'e',ex_key:'p4',set_idx:0,done:false,reps_target:'10',weight:40,actual_reps:9},{id:'f',ex_key:'p4',set_idx:1,done:false,reps_target:'10'}]
},board2);
h.failIds.add('f');
h.markPlanned('2026-10-26T15:00:00.000Z').then(failed=>{
  assert.equal(failed,1,'cuenta lo que no se guardó');
  const byId=Object.fromEntries(h.updates.map(u=>[u.id,u.patch]));
  assert.equal(byId.a,undefined,'lo ya palomeado no se toca');
  assert.equal(byId.b.actual_reps,6,'un rango se registra por el piso');
  assert.equal(byId.c.actual_seconds,30,'un aguante, por su tiempo objetivo');
  assert.equal(byId.d.actual_reps,null,'al fallo no se supone');
  assert.equal(byId.e.actual_reps,9,'la marca sembrada de la vez pasada manda sobre el objetivo');
  assert.equal(byId.e.weight,40);
  assert.ok(Object.values(byId).every(p=>p.done===true&&p.updated_at==='2026-10-26T15:00:00.000Z'));
  const sets=h.sets();
  assert.equal(sets.p1[1].done,true);
  assert.equal(sets.p4[1].done,false,'la que falló sigue pendiente');
  assert.equal(h.logged.length,4,'cada serie guardada pasa al historial');
  console.log('HABIT Cambiar/agregar/cerrar: '+'ok');
}).catch(e=>{console.error(e);process.exit(1);});
