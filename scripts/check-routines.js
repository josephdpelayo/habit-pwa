// Exercise production routine search, detail rendering and selection using local fixtures.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const app=fs.readFileSync(require('node:path').join(__dirname,'../app.html'),'utf8');
function source(a,b){const start=app.indexOf(a),end=app.indexOf(b,start);assert.ok(start>=0&&end>start);return app.slice(start,end);}
const catalog=Array.from({length:30},(_,i)=>({id:'ex'+i,slug:'ex'+i,name:'Ejercicio '+i,primary_muscle:'Espalda',aliases:[],equipment:[]}));
catalog.push({id:'press',slug:'press',name:'Press inclinado',primary_muscle:'Pecho',aliases:['Incline press'],equipment:['Mancuernas'],video_url:'https://example.com/demo.mp4'});
catalog.push({id:'curl',slug:'curl',name:'Curl de bíceps',primary_muscle:'Bíceps',aliases:[],equipment:['Barra']});
const h=new Function('catalog',`
  let _rbPickerQuery='',_rbPickerMuscle='',_rbPickerFor=null,_rbDraft={name:'Mi rutina',exercises:[]};
  const nodes=new Map();
  const document={getElementById:id=>{if(!nodes.has(id))nodes.set(id,{innerHTML:'',textContent:'',value:'',focus(){}});return nodes.get(id);}};
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const exerciseCatalogRows=()=>catalog,wsCatalogRowBySlug=slug=>catalog.find(e=>e.slug===slug);
  const rbSyncFromDom=()=>{},renderRoutineBuilder=()=>{},hideTrainingDialog=()=>{},showTrainingDialog=()=>{};
  const routineExercises=b=>b.exercises||[],routineTodayMeta=b=>({duration:30,equipment:[]});
  const exerciseSetCount=ex=>Number(ex.sets)||3,exerciseTargetLabel=ex=>ex.reps||'';
  let board={id:'b',name:'Routine <test>',owner_id:'me',exercises:catalog.slice(0,8).map(e=>({...e,sets:3,reps:'8-10'}))};
  const routineById=()=>board,isMyRoutine=b=>b.owner_id==='me';
  ${source('function wsPickItemHtml(', 'function wsToggleSwap(')}
  ${source('function rbClosePicker(', '// Al elegir del catálogo')}
  ${source('function rbPickExercise(', 'function rbRemoveEx(')}
  ${source('function openRoutineDetail(', 'function closeRoutineDetail(')}
  return {search:(q,m='')=>{_rbPickerQuery=q;_rbPickerMuscle=m;return rbPickerMatches();},
    pick:(target,slug)=>{_rbPickerFor=target;rbPickExercise(slug);return _rbDraft;},
    draft:()=>_rbDraft,cancel:rbClosePicker,
    detail:(mine=true)=>{board.owner_id=mine?'me':null;openRoutineDetail('b');return nodes.get('routine-detail-body').innerHTML;}};
`)(catalog);
assert.equal(h.search('').length,32);
assert.equal(h.search('biceps')[0].slug,'curl');
assert.equal(h.search('incline')[0].slug,'press');
assert.equal(h.search('press mancuernas')[0].slug,'press');
assert.equal(h.search('','Espalda').length,30);
assert.equal(h.search('press','Espalda').length,0);
assert.equal(h.search('nonexistent').length,0);
h.pick('new','press');
assert.equal(h.draft().exercises.length,1);
assert.equal(h.draft().name,'Mi rutina');
assert.equal(h.draft().exercises[0].video_url,catalog[30].video_url);
h.draft().exercises[0].sets='5';
h.draft().exercises[0].id='stable';
h.pick(0,'curl');
assert.equal(h.draft().exercises.length,1);
assert.equal(h.draft().exercises[0].sets,'5');
assert.equal(h.draft().exercises[0].id,'stable');
assert.equal(h.draft().exercises[0].video_url,undefined);
h.cancel();
assert.equal(h.draft().exercises.length,1);
const detail=h.detail();
assert.equal((detail.match(/<li>/g)||[]).length,8);
assert.match(detail,/Routine &lt;test&gt;/);
assert.match(detail,/Editar rutina/);
assert.match(detail,/Eliminar rutina/);
const coach=h.detail(false);
assert.match(coach,/Duplicar y adaptar/);
assert.doesNotMatch(coach,/Eliminar rutina|Editar rutina/);
console.log('HABIT Rutinas: 21 assertions OK');
