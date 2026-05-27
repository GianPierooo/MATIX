// Matix — Calendario · vista Semana

const CW = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  plus: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>,
  mic: <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  chevL: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  chevR: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>,
  home: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/></svg>,
  tasks: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/></svg>,
  cal: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  uni: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  notes: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
};

const DAYS = [
  {dow:'L', d:18}, {dow:'M', d:19}, {dow:'X', d:20}, {dow:'J', d:21},
  {dow:'V', d:22}, {dow:'S', d:23, today:true}, {dow:'D', d:24},
];

// Events: { dayIndex: [{start, end, label, color}] } - hours in float
const EV = {
  0: [
    {s:9,   e:10.5, l:'Cálculo III', c:CW.accent},
    {s:14,  e:15.5, l:'Estadística II', c:CW.green},
    {s:18,  e:19,   l:'Gimnasio', c:CW.amber},
  ],
  1: [
    {s:8,   e:9.5,  l:'Estadística II', c:CW.green},
    {s:14,  e:15.5, l:'Sistemas', c:CW.amber},
    {s:19,  e:20.5, l:'Reunión tutor', c:CW.purple},
  ],
  2: [
    {s:9,   e:10.5, l:'Cálculo III', c:CW.accent},
    {s:14,  e:15.5, l:'Sistemas', c:CW.amber},
  ],
  3: [
    {s:8,   e:9.5,  l:'Estadística II', c:CW.green},
    {s:11,  e:13,   l:'Lab Física', c:CW.red},
  ],
  4: [
    {s:9,   e:10.5, l:'Sistemas', c:CW.amber},
    {s:18,  e:20,   l:'Filosofía', c:CW.purple},
    {s:23,  e:23.99, l:'Entrega Física', c:CW.red},
  ],
  5: [ // Sat = today
    {s:11,  e:12.5, l:'Repaso Cálculo', c:CW.amber},
    {s:14,  e:15.5, l:'Cálculo III', c:CW.accent},
    {s:18,  e:19,   l:'Gimnasio', c:CW.green},
    {s:23,  e:23.99, l:'Entrega Cálc.', c:CW.red},
  ],
  6: [
    {s:10,  e:12,   l:'Estudiar', c:CW.accent},
  ],
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px', gap:10}}>
      <a href="Calendario.html" style={{width:40, height:40, borderRadius:12, background:CW.card, color:CW.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none', flexShrink:0}}>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
      </a>
      <div style={{display:'flex', flexDirection:'column', flex:1, minWidth:0}}>
        <span style={{fontSize:12, color:CW.muted, fontWeight:500}}>Semana 21 · Mayo</span>
        <span style={{fontSize:22, color:CW.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>18 — 24 mayo</span>
      </div>
      <a href="Nuevo%20Evento.html" style={{width:40, height:40, borderRadius:12, background:CW.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 6px 16px rgba(45,127,249,0.35)', textDecoration:'none', flexShrink:0}}>{ic.plus}</a>
    </div>
  );
}

function Segmented() {
  const opts = [
    {l:'Mes', href:'Calendario.html'},
    {l:'Semana', active:true},
    {l:'Día', href:'Calendario%20Dia.html'},
  ];
  return (
    <div style={{margin:'4px 20px 10px', background:CW.card, padding:4, borderRadius:12, display:'flex', gap:4}}>
      {opts.map(o => (
        <a key={o.l} href={o.href || '#'} style={{flex:1, padding:'8px 0', textAlign:'center', borderRadius:9, background:o.active?CW.accent:'transparent', color:o.active?'#fff':CW.muted, fontSize:13, fontWeight:600, boxShadow:o.active?'0 4px 14px rgba(45,127,249,0.35)':'none', textDecoration:'none'}}>{o.l}</a>
      ))}
    </div>
  );
}

function WeekHeader() {
  return (
    <div style={{display:'grid', gridTemplateColumns:'34px repeat(7, 1fr)', padding:'6px 12px 6px 14px', borderBottom:`1px solid ${CW.hairline}`, position:'sticky', top:0, background:CW.bg, zIndex:2}}>
      <div/>
      {DAYS.map((d,i) => (
        <div key={i} style={{display:'flex', flexDirection:'column', alignItems:'center', gap:4, padding:'4px 0'}}>
          <span style={{fontSize:9.5, color:CW.muted, fontWeight:600, letterSpacing:0.6}}>{d.dow}</span>
          <span style={{
            width:24, height:24, borderRadius:'50%',
            background: d.today?CW.accent:'transparent',
            color: d.today?'#fff':CW.text,
            display:'flex', alignItems:'center', justifyContent:'center',
            fontSize:12, fontWeight:d.today?700:600,
            boxShadow: d.today?`0 4px 10px ${hexA(CW.accent,0.45)}`:'none',
          }}>{d.d}</span>
        </div>
      ))}
    </div>
  );
}

const HOURS = [8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23];
const HOUR_H = 38;

function Grid() {
  return (
    <div style={{position:'relative'}}>
      {/* hour rows */}
      <div style={{display:'grid', gridTemplateColumns:'34px repeat(7, 1fr)'}}>
        {HOURS.map((h,i) => (
          <React.Fragment key={i}>
            <div style={{height:HOUR_H, padding:'4px 6px 0 8px', borderBottom:`1px solid ${CW.hairline}`, fontSize:9.5, color:CW.muted, fontWeight:600, textAlign:'right'}}>
              {h}:00
            </div>
            {DAYS.map((_,di) => (
              <div key={di} style={{height:HOUR_H, borderBottom:`1px solid ${CW.hairline}`, borderLeft:di===0?'none':`1px dashed ${hexA(CW.muted,0.10)}`, background:DAYS[di].today?hexA(CW.accent,0.04):'transparent'}}/>
            ))}
          </React.Fragment>
        ))}
      </div>

      {/* events absolutely positioned over grid */}
      <div style={{position:'absolute', top:0, left:34, right:0, bottom:0, display:'grid', gridTemplateColumns:'repeat(7, 1fr)', pointerEvents:'none'}}>
        {DAYS.map((_,di) => (
          <div key={di} style={{position:'relative'}}>
            {(EV[di] || []).map((ev,i) => {
              const startH = HOURS[0];
              const top = (ev.s - startH) * HOUR_H;
              const height = Math.max(14, (ev.e - ev.s) * HOUR_H - 2);
              return (
                <div key={i} style={{
                  position:'absolute', top, left:2, right:2, height,
                  background: hexA(ev.c, 0.22),
                  borderLeft: `2.5px solid ${ev.c}`,
                  borderRadius:6,
                  padding:'2px 4px',
                  overflow:'hidden',
                  boxShadow: `0 2px 8px ${hexA(ev.c, 0.18)}`,
                }}>
                  <div style={{fontSize:8.5, fontWeight:700, color:ev.c, letterSpacing:0.2, lineHeight:1.15, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{ev.l}</div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* now line */}
      <NowLine/>
    </div>
  );
}

function NowLine() {
  // 9:45 on Saturday (index 5)
  const top = (9.75 - HOURS[0]) * HOUR_H;
  return (
    <div style={{position:'absolute', left:34, right:0, top, display:'grid', gridTemplateColumns:'repeat(7, 1fr)', pointerEvents:'none', zIndex:3}}>
      <div/><div/><div/><div/><div/>
      <div style={{position:'relative'}}>
        <div style={{position:'absolute', left:-6, top:-5, width:10, height:10, borderRadius:'50%', background:CW.red, boxShadow:`0 0 10px ${CW.red}`}}/>
        <div style={{position:'absolute', left:0, right:0, top:0, height:2, background:CW.red, boxShadow:`0 0 8px ${hexA(CW.red,0.6)}`}}/>
      </div>
      <div/>
    </div>
  );
}

function FAB() {
  return (
    <div style={{position:'absolute', right:18, bottom:96, width:60, height:60, borderRadius:'50%', background:CW.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)'}}>{ic.mic}</div>
  );
}

function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ic.home},
    {key:'tasks', label:'Tareas', icon:ic.tasks},
    {key:'cal', label:'Calendario', icon:ic.cal, active:true},
    {key:'uni', label:'Universidad', icon:ic.uni},
    {key:'notes', label:'Apuntes', icon:ic.notes},
  ];
  return (
    <div style={{background:CW.bg, borderTop:`1px solid ${CW.hairline}`, padding:'10px 8px 8px', display:'flex', justifyContent:'space-around'}}>
      {items.map(it => (
        <div key={it.key} style={{display:'flex', flexDirection:'column', alignItems:'center', gap:4, flex:1, padding:'4px 0', color:it.active?CW.accent:CW.muted}}>
          {it.active ? <div style={{padding:'4px 14px', borderRadius:999, background:'rgba(45,127,249,0.16)', display:'flex', alignItems:'center', justifyContent:'center'}}>{it.icon}</div> : it.icon}
          <span style={{fontSize:10.5, fontWeight:it.active?600:500}}>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:CW.bg, color:CW.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <Segmented/>
      <WeekHeader/>
      <div style={{flex:1, overflowY:'auto', paddingBottom:96, position:'relative'}}>
        <Grid/>
      </div>
      <MatixFAB/>
      <MatixBottomNav active="home"/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
