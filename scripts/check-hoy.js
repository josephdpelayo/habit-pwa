// Exercise the real Hoy renderer and session restoration with local fixtures only.
// No browser session, credentials, network request, or database write is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '../app.html'), 'utf8');
function between(start, end) {
  const first = app.indexOf(start);
  const last = app.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `${start} found in app.html`);
  return app.slice(first, last);
}
function lineFunction(name) {
  const match = app.match(new RegExp(`^function ${name}\\([^\\n]+$`, 'm'));
  assert.ok(match, `${name} found in app.html`);
  return match[0];
}

const source = [
  between('function parsePyramidReps(', 'function repsTargetForSet('),
  between('function parseDS(', 'function mazDateMs('),
  between('function dateObjFromDS(', 'function mazLocalDateTimeIso('),
  lineFunction('routineExercises'),
  lineFunction('isCoachSet'),
  between('function routineTodayMeta(', 'function nextExerciseSuggestion('),
  between('function sessionExerciseList(', 'function buildTrainingExerciseSnapshot('),
  between('function exerciseKeyForSession(', 'function isSetPending('),
  between('function hoyHeroHtml(', '// ── SEMANA'),
  between('async function loadSessionSetsSb(', 'async function hydrateSessionSetDefaults('),
  between('let _activeCoachingSessionLoad=', 'function showActiveSessionBar('),
  between('async function renderRutHub(', '// Un socio tiene tres orígenes de rutina:'),
  between('const DOOR_TRAIN_KEY=', 'async function doorTrainingPrompt(')
].join('\n');

const makeHarness = new Function(`
  const today='2026-10-23';
  const DOW_SHORT=['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'];
  const DOW_LONG=['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
  const pad=n=>String(n).padStart(2,'0');
  const mazToday=()=>today;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let coachWeekStart='2026-10-19', coachSchedule=[], coachBoardsById={};
  let activeCoachingSession=null, coachSessionSets={}, hoyBodyOpen=false, myRecovery=[];
  let sbUser={id:'member'}, wsPausedMs=0, wsPausedAt=0;
  let rutActiveTab='hoy', myRoutinesLoadedAt=1, recoveryLoadedAt=Date.now(), myRoutines=[];
  const routineById=id=>myRoutines.find(b=>b.id===id)||coachBoardsById[id]||null;
  const routineColor=b=>(b&&b.color)||'#2563eb';
  const fmtDS=ds=>ds, dsFromIsoMaz=iso=>String(iso||'').slice(0,10);
  const RECOVERY_TTL_MS=60000;
  const panel={innerHTML:''};
  const document={getElementById:id=>id==='rut-hoy-content'?panel:null};
  const window={};
  const navigator={onLine:true};
  let cached=null, activeResult={data:null}, setsResult={data:[]}, recentResult={data:[]};
  let activeRead=()=>activeResult;
  const calls={active:0,sets:0,errors:[]};
  const console={error:(...args)=>calls.errors.push(args),warn:()=>{}};
  const sb={from:table=>{
    const chain={select:()=>chain,eq:()=>chain,order:()=>chain,limit:()=>chain};
    chain.maybeSingle=async()=>{calls.active++;return activeRead();};
    chain.then=(resolve,reject)=>{
      if(table==='coaching_schedule')return Promise.resolve(recentResult).then(resolve,reject);
      if(table!=='coaching_session_sets')throw new Error('Unexpected table '+table);
      calls.sets++;
      return Promise.resolve(setsResult).then(resolve,reject);
    };
    return chain;
  }};
  const cacheActiveTrainingSession=row=>{cached=row;};
  const readCachedTrainingSession=()=>cached;
  const showActiveSessionBar=()=>{}, wsStartTicker=()=>{}, updateCoachingNavBadge=()=>{};
  const renderInicioCoachingWidgets=()=>{}, hydrateSessionSetDefaults=async()=>{};
  const loadMyRoutinesSb=async()=>{}, loadCoachWeekDataSb=async()=>{}, loadWeekPlanSb=async()=>{};
  const loadMyRecoverySb=async()=>{}, renderRutSemana=()=>{}, renderRutRutinas=()=>{};
  const trainingSyncClass=()=>'', trainingSyncText=()=>'Guardado';
  const muscleLabelEs=x=>x, formatHoursEs=x=>x+' h', bodyCardHtml=()=>'<div>body detail</div>';
  ${source}
  return {
    set:state=>{
      if('schedule' in state)coachSchedule=state.schedule;
      if('active' in state)activeCoachingSession=state.active;
      if('sets' in state)coachSessionSets=state.sets;
      if('boards' in state)coachBoardsById=state.boards;
      if('cached' in state)cached=state.cached;
      if('activeResult' in state)activeResult=state.activeResult;
      if('setsResult' in state)setsResult=state.setsResult;
      if('activeRead' in state)activeRead=state.activeRead;
      if('online' in state)navigator.onLine=state.online;
      if('bodyOpen' in state)hoyBodyOpen=state.bodyOpen;
      if('routines' in state)myRoutines=state.routines;
      if('recent' in state){hoyRecentSessions=state.recent;recentResult={data:state.recent};}
    },
    render:()=>{renderRutHoy();return panel.innerHTML;},
    week:hoyWeekHtml,
    order:hoyRoutineOrder,
    repeatable:hoyRepeatable,
    doorChoices:doorTrainChoices,
    restore:loadActiveCoachingSessionSb,
    hub:renderRutHub,
    html:()=>panel.innerHTML,
    state:()=>({active:activeCoachingSession,sets:coachSessionSets,cached}),
    calls
  };
`);

const board = {id:'b1', exercises:[
  {id:'squat',name:'Sentadilla',sets:3,reps:'10'},
  {id:'row',name:'Remo',sets:3,reps:'12'}
]};
const session = (id, status, extra={}) => ({
  id, status, ds:'2026-10-23', board_id:'b1', board_name:'Fuerza', board_color:'#123456',
  created_by:'member', ...extra
});
const isFriday = state => new RegExp(`hoy-day ${state} today`);
let checks=0;
const check=(condition,message)=>{assert.ok(condition,message);checks++;};

async function run() {
  let h=makeHarness();
  let html=h.render();
  check(html.includes('Empieza a entrenar')&&html.includes('Elegir qué entrenar'), 'new member can choose training');
  check(html.includes('Armar mi semana')&&html.includes('Sin plan'), 'new member can build a week');
  check((html.match(/class="hoy-day /g)||[]).length===7, 'week shows seven days');
  check(!html.includes('body detail')&&html.includes('aria-expanded="false"'), 'body starts collapsed');
  h.set({bodyOpen:true});
  check(h.render().includes('body detail'), 'body can be expanded');

  h=makeHarness();
  h.set({schedule:[session('scheduled','scheduled',{created_by:'coach'})], boards:{b1:board}});
  html=h.render();
  check(html.includes('2 ejercicios · ~15 min · de tu coach'), 'scheduled card describes real routine and coach');
  check(html.includes('startCoachingSessionSb(&quot;scheduled&quot;)'), 'scheduled CTA starts its session');
  check(isFriday('planned').test(html)&&html.includes('0 de 1'), 'scheduled day is pending');

  const live=session('live','in_progress',{exercise_snapshot:board.exercises});
  const sets={squat:[{done:true},{done:true},{done:true}],row:[{done:false},{done:false},{done:false}]};
  h=makeHarness();
  h.set({schedule:[live],active:live,sets});
  html=h.render();
  check(html.includes('En curso')&&html.includes('openWorkoutSheet()'), 'live CTA continues the session');
  check(html.includes('3 de 6 series · Sigue: Remo'), 'live progress and next exercise match session sets');
  check(isFriday('live').test(html)&&html.includes('0 de 1'), 'live day is not counted as complete');
  h.set({sets:{}});
  check(!h.render().includes('0 de 0')&&h.render().includes('Retoma tu sesión'), 'unavailable or empty sets do not invent progress');

  h=makeHarness();
  h.set({schedule:[session('done','done',{duration_sec:2700})]});
  html=h.render();
  check(html.includes('Hecho ✓ · 45 min'), 'completed card uses recorded duration');
  check(html.includes('openEditCompletedWorkoutSb(&quot;done&quot;)'), 'completed CTA opens its recorded workout');
  check(isFriday('done').test(html)&&html.includes('1 de 1'), 'fully completed day is counted once');

  h=makeHarness();
  h.set({schedule:[session('next','scheduled',{ds:'2026-10-24',board_name:'Pierna'})]});
  html=h.render();
  check(html.includes('Descanso')&&html.includes('Lo que sigue: sábado · Pierna'), 'rest day shows the next scheduled workout');
  check(html.includes('Entrenar de todos modos'), 'rest day keeps optional training available');
  h.set({schedule:[session('skip','skipped')]});
  html=h.render();
  check(html.includes('Recuperar también es parte del plan.')&&!html.includes('Empieza a entrenar'), 'an intentionally skipped day is rest, not a new member');

  h=makeHarness();
  h.set({schedule:[session('done','done'),live],active:live,sets});
  html=h.render();
  check(isFriday('live').test(html)&&html.includes('0 de 1'), 'a completed workout cannot hide another live workout');
  h.set({schedule:[session('done','done'),session('pending','scheduled')],active:null});
  html=h.render();
  check(isFriday('planned').test(html)&&html.includes('0 de 1'), 'a day with another workout pending stays incomplete');
  check(html.includes('startCoachingSessionSb(&quot;pending&quot;)'), 'pending workout takes priority over earlier completion');
  h.set({schedule:[session('one','done'),session('two','done')]});
  check(isFriday('done').test(h.render())&&h.render().includes('1 de 1'), 'two completed workouts count as one completed day');
  h.set({schedule:[session('one','done'),session('skip','skipped')]});
  check(isFriday('done').test(h.render()), 'skipped workouts do not prevent a completed training day');
  h.set({schedule:[session('first','scheduled'),session('second','scheduled')],boards:{b1:board}});
  html=h.render();
  check((html.match(/class="hoy-also"/g)||[]).length===1&&html.includes('startCoachingSessionSb(&quot;second&quot;)'), 'second scheduled workout gets a separate actionable row');
  h.set({active:live,sets});
  check((h.render().match(/class="hoy-also"/g)||[]).length===2, 'all pending workouts remain visible alongside a live session');
  h.set({schedule:[session('past','scheduled',{ds:'2026-10-19'})],active:null});
  check(/hoy-day missed/.test(h.week()), 'missed workouts are distinct from future workouts');

  h=makeHarness();
  h.set({schedule:[live],activeResult:{data:live},setsResult:{data:[
    {id:'s1',ex_key:'squat',set_idx:0,done:true},
    {id:'s2',ex_key:'row',set_idx:0,done:false}
  ]}});
  await h.hub();
  check(h.html().includes('1 de 2 series · Sigue: Remo'), 'opening Hoy after reload waits for restored session sets');
  check(h.calls.active===1&&h.calls.sets===1, 'restoration fetches one session and one set list');
  await h.restore();
  check(h.calls.sets===1, 'restoring the same loaded session preserves local set progress');

  h=makeHarness();
  let release;
  h.set({activeRead:()=>new Promise(resolve=>{release=resolve;})});
  const first=h.restore(), second=h.restore();
  release({data:live});
  await Promise.all([first,second]);
  check(h.calls.active===1&&h.calls.sets===1, 'startup and Hoy share one pending restoration');

  h=makeHarness();
  h.set({schedule:[live],activeResult:{data:live},setsResult:{error:new Error('offline')}});
  await h.hub();
  check(h.html().includes('Continuar')&&!h.html().includes('0 de 0'), 'failed set hydration keeps a truthful resume action');
  check(h.calls.errors.length===1, 'set load failure remains observable');

  h=makeHarness();
  h.set({active:live,sets,cached:live,online:false,activeResult:{error:new Error('offline')}});
  await h.restore();
  check(h.state().sets.row.length===3&&h.calls.sets===0, 'offline restore keeps existing locally loaded sets');
  h=makeHarness();
  h.set({cached:live,online:false,activeResult:{error:new Error('offline')}});
  await h.restore();
  check(h.render().includes('Continuar')&&!h.render().includes('0 de 0'), 'offline cold restore does not invent set totals');
  h.set({online:true,activeResult:{data:null},sets});
  await h.restore();
  check(h.state().active===null&&Object.keys(h.state().sets).length===0, 'a finished session cannot leave stale live sets behind');

  h=makeHarness();
  h.set({schedule:[session('escaped','scheduled',{board_name:'<img onerror="alert(1)">'})],boards:{b1:board}});
  html=h.render();
  check(!html.includes('<img onerror=')&&html.includes('&lt;img'), 'routine names are escaped');

  // Repetir el último: cuando hoy no hay nada agendado, lo más corto es repetirlo.
  const doneRow=(id,extra={})=>({id,status:'done',ds:'2026-10-21',board_id:'b1',board_name:'Fuerza',board_color:'#123456',
    completed_at:'2026-10-21T15:00:00Z',duration_sec:2760,session_exercises:[],...extra});
  h=makeHarness();
  h.set({recent:[doneRow('d1')]});
  html=h.render();
  check(html.includes('Fuerza')&&html.includes('hoyRepeatLast()')&&html.includes('>Repetir<'), 'no plan with history offers to repeat the last workout');
  check(html.includes('Lo último que hiciste, el miércoles · 46 min'), 'repeat card says when and how long');
  check(html.includes('Elegir otra cosa')&&!html.includes('Empieza a entrenar'), 'repeat card keeps the picker one tap away');
  h.set({schedule:[session('next','scheduled',{ds:'2026-10-24',board_name:'Pierna'})]});
  html=h.render();
  check(html.includes('Descanso')&&html.includes('Repetir Fuerza')&&html.includes('Entrenar otra cosa'), 'rest day offers repeat as the optional workout');
  const emptyFree=doneRow('free0',{board_id:null,board_name:'Entreno libre'});
  const free=doneRow('free1',{board_id:null,board_name:'Entreno libre',session_exercises:[{ex_key:'cat-dominadas',name:'Dominadas'}]});
  check(h.repeatable([emptyFree,free])===free, 'an empty free workout is skipped, one with exercises can be repeated');
  check(h.repeatable([doneRow('gone',{board_id:null,session_exercises:[{replaces:'a',removed:true}]})])===null, 'a free workout with only removals has nothing to repeat');
  h.set({schedule:[session('done','done')]});
  check(!h.render().includes('hoyRepeatLast()'), 'a day already trained shows what was done, not repeat');

  // Tus rutinas en Hoy: la reciente primero, la de la tarjeta no se repite.
  const rt=(id,name)=>({id,name,color:'#2563eb',exercises:[{id:id+'e',name:'Ej',sets:3,reps:'10'}]});
  const routines=[rt('mine','Mía'),rt('coach','Coach'),rt('basic','Básica')];
  h=makeHarness();
  check(h.order(routines,[doneRow('x',{board_id:'basic'})],null).map(b=>b.id).join()==='basic,mine,coach', 'recently trained routine goes first, then the usual order');
  check(h.order(routines,[],'mine').map(b=>b.id).join()==='coach,basic', 'the routine already on the card is not repeated');
  check(h.order(Array.from({length:12},(_,i)=>rt('r'+i,'R'+i)),[],null).length===8, 'the row is capped');
  h.set({routines,schedule:[session('scheduled','scheduled',{board_id:'mine'})],boards:{mine:routines[0]}});
  html=h.render();
  check(html.includes('Tus rutinas')&&html.includes('hoyStartRoutine(&quot;coach&quot;)')&&!html.includes('hoyStartRoutine(&quot;mine&quot;)'), 'Hoy lists the other routines');
  check(html.includes('1 ejercicio · ~')&&html.includes('Ver todas'), 'routine chips describe themselves and link to the full list');
  h.set({schedule:[],boards:{},recent:[doneRow('d',{board_id:'coach',board_name:'Coach'})]});
  html=h.render();
  check(html.includes('hoyRepeatLast()')&&!html.includes('hoyStartRoutine(&quot;coach&quot;)')&&html.includes('hoyStartRoutine(&quot;mine&quot;)'), 'the routine offered to repeat is not repeated in the row');
  h.set({active:live,sets});
  check(!h.render().includes('hoy-routines'), 'no routine row while a workout is live');
  h=makeHarness();
  check(!h.render().includes('hoy-routines'), 'no routine row without routines');

  // De la puerta al entreno.
  h=makeHarness();
  let door=h.doorChoices({pending:[session('p1','scheduled',{board_name:'Empuje',board_id:'e'})],last:doneRow('d',{board_id:'t',board_name:'Tirón'})});
  check(door.body==='Hoy toca Empuje.'&&door.choices.map(c=>c.key).join()==='s:p1,repeat,pick', 'door offers today first, then repeat, then other');
  check(door.choices[0].label==='Empuje ▶'&&door.choices[2].label==='Otra cosa', 'door labels are short');
  door=h.doorChoices({pending:[session('p1','scheduled',{board_id:'t'})],last:doneRow('d',{board_id:'t'})});
  check(!door.choices.some(c=>c.key==='repeat'), 'repeat is not offered when it is the same as today');
  door=h.doorChoices({});
  check(door.choices.length===1&&door.choices[0].label==='Elegir qué entrenar', 'a member with no history just picks');
  door=h.doorChoices({active:live,pending:[session('p1','scheduled')]});
  check(door.choices.length===1&&door.choices[0].key==='resume', 'a live workout is resumed, not doubled');

  console.log('HABIT Hoy: '+checks+' assertions OK');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
