const assert = require('node:assert/strict');
const fs = require('node:fs');

const html = fs.readFileSync('skandi.html', 'utf8');
const migration = fs.readFileSync('migrations/102_skandi_program_owns_the_week.sql', 'utf8');
const cycleStart = html.indexOf('function currentTrainingBlock()');
const cycleEnd = html.indexOf('// Deload-week load suggestion');
const programStart = html.indexOf('const myTemplates=');
const programEnd = html.indexOf('// One row per weekday', programStart);

assert.ok(cycleStart >= 0 && cycleEnd > cycleStart, 'cycle helpers found');
assert.ok(programStart >= 0 && programEnd > programStart, 'program helpers found');

const applyStart = html.indexOf('async function applyProgram(');
const applyEnd = html.indexOf('async function deleteProgram(', applyStart);
const applySource = html.slice(applyStart, applyEnd);
assert.ok(applyStart >= 0 && applyEnd > applyStart, 'applyProgram found');
assert.doesNotMatch(applySource, /from\('skandi_templates'\)/, 'activation does not move routines');
assert.doesNotMatch(applySource, /from\('skandi_activity_templates'\)/, 'activation does not move endurance templates');
assert.match(applySource, /start_date:todayKey\(\)/, 'activation starts the program cycle');
assert.match(migration, /and p_week_index >= 0/, 'ended cycles resolve to no program slots');
assert.match(migration, /case when v_program is null then 'template' else 'program' end/, 'calendar records its source');

const source = `
let state;
const t=(key,params={})=>key+JSON.stringify(params);
const mondayOf=date=>{const d=new Date(date);d.setHours(0,0,0,0);d.setDate(d.getDate()-((d.getDay()+6)%7));return d;};
const keyToDate=key=>new Date(key+'T00:00:00');
${html.slice(cycleStart, cycleEnd)}
${html.slice(programStart, programEnd)}
const key=d=>[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');
const monday=mondayOf(new Date());
const baseState=()=>({
  user:{id:'u1'},trainingBlocks:[],
  templates:[{id:'t1',user_id:'u1',weekday:0},{id:'t2',user_id:'u1',weekday:2}],
  activityTemplates:[{id:'a1',user_id:'u1',weekday:1}],
  programs:[],programDays:[]
});

state=baseState();
assert.deepEqual(weekPlan().map(d=>[d.template_id,d.activity_template_id]),
  [['t1',null],[null,'a1'],['t2',null],[null,null],[null,null],[null,null],[null,null]]);

state=baseState();
state.programs=[{id:'p1',is_active:true,start_date:key(monday),weeks:4,deload_week:true}];
state.programDays=[
  {program_id:'p1',week_index:0,weekday:0,sort_order:0,template_id:'t2',activity_template_id:'a1'},
  {program_id:'p1',week_index:0,weekday:2,sort_order:0,template_id:'t1',activity_template_id:null},
  {program_id:'p1',week_index:2,weekday:0,sort_order:0,template_id:null,activity_template_id:'a2'}
];
assert.deepEqual(weekPlan(1)[0],{template_id:'t2',activity_template_id:'a1'});
assert.deepEqual(weekPlan(2)[0],{template_id:null,activity_template_id:'a2'});
assert.equal(currentWeekSnapshot().length,2);
assert.equal(weekMatchesProgram(state.programs[0]),true);
let info=trainingBlockWeekInfo();
assert.equal(info.totalWeeks,5);
assert.equal(info.week,1);
assert.equal(info.program.id,'p1');

state.programs[0].deload_week=false;
info=trainingBlockWeekInfo();
assert.equal(info.totalWeeks,4);
assert.equal(info.deload,false);

state.programs[0].deload_week=true;
const ended=new Date(monday); ended.setDate(ended.getDate()-6*7);
state.programs[0].start_date=key(ended);
assert.ok(programWeekIndex(state.programs[0])>programCycleLength(state.programs[0]));
assert.ok(weekPlan().every(d=>!d.template_id&&!d.activity_template_id));

console.log('P2 program resolver: 20 assertions OK');
`;

new Function('assert', source)(assert);
