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
  between('async function renderRutHub(', '// Un socio tiene tres orígenes de rutina:')
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
  let rutActiveTab='hoy', myRoutinesLoadedAt=1, recoveryLoadedAt=Date.now();
  const RECOVERY_TTL_MS=60000;
  const panel={innerHTML:''};
  const document={getElementById:id=>id==='rut-hoy-content'?panel:null};
  const window={};
  const navigator={onLine:true};
  let cached=null, activeResult={data:null}, setsResult={data:[]};
  let activeRead=()=>activeResult;
  const calls={active:0,sets:0,errors:[]};
  const console={error:(...args)=>calls.errors.push(args)};
  const sb={from:table=>{
    const chain={select:()=>chain,eq:()=>chain,order:()=>chain,limit:()=>chain};
    chain.maybeSingle=async()=>{calls.active++;return activeRead();};
    chain.then=(resolve,reject)=>{
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
    },
    render:()=>{renderRutHoy();return panel.innerHTML;},
    week:hoyWeekHtml,
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

  console.log('HABIT Hoy: '+checks+' assertions OK');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
