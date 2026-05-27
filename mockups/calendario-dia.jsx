// Matix — Calendario · vista Día

const CD = {
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
  home: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/></svg>,
  tasks: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/></svg>,
  cal: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  uni: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  notes: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
  pin: <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.4"/></svg>,
  spark: <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px', gap:10}}>
      <a href="Calendario.html" style={{width:40, height:40, borderRadius:12, background:CD.card, color:CD.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none', flexShrink:0}}>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
      </a>
      <div style={{display:'flex', flexDirection:'column', flex:1, minWidth:0}}>
        <span style={{fontSize:12, color:CD.muted, fontWeight:500}}>Hoy</span>
        <span style={{fontSize:22, color:CD.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>Sábado 23 mayo</span>
      </div>
      <a href="Nuevo%20Evento.html" style={{width:40, height:40, borderRadius:12, background:CD.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 6px 16px rgba(45,127,249,0.35)', textDecoration:'none', flexShrink:0}}>{ic.plus}</a>
    </div>
  );
}

function Segmented() {
  const opts = [
    {l:'Mes', href:'Calendario.html'},
    {l:'Semana', href:'Calendario%20Semana.html'},
    {l:'Día', active:true},
  ];
  return (
    <div style={{margin:'4px 20px 10px', background:CD.card, padding:4, borderRadius:12, display:'flex', gap:4}}>
      {opts.map(o => (
        <a key={o.l} href={o.href || '#'} style={{flex:1, padding:'8px 0', textAlign:'center', borderRadius:9, background:o.active?CD.accent:'transparent', color:o.active?'#fff':CD.muted, fontSize:13, fontWeight:600, boxShadow:o.active?'0 4px 14px rgba(45,127,249,0.35)':'none', textDecoration:'none'}}>{o.l}</a>
      ))}
    </div>
  );
}

// Mini week strip
function MiniStrip() {
  const days = ['L18','M19','X20','J21','V22','S23','D24'];
  return (
    <div style={{padding:'4px 16px 10px', display:'flex', gap:6}}>
      {days.map((d,i) => {
        const today = i === 5;
        return (
          <div key={i} style={{
            flex:1, padding:'8px 0', borderRadius:12, textAlign:'center',
            background: today ? CD.accent : CD.card,
            color: today ? '#fff' : CD.muted,
            fontSize:11.5, fontWeight: today?700:500,
            boxShadow: today ? `0 4px 14px ${hexA(CD.accent,0.35)}` : 'none',
            position:'relative',
          }}>
            {d}
            {!today && [0,1,2,4].includes(i) && (
              <div style={{display:'flex', gap:2, justifyContent:'center', marginTop:3}}>
                <span style={{width:3, height:3, borderRadius:'50%', background:CD.accent}}/>
                {i===4 && <span style={{width:3, height:3, borderRadius:'50%', background:CD.red}}/>}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// All-day events at top
function AllDay() {
  return (
    <div style={{padding:'0 16px 12px'}}>
      <div style={{fontSize:10, fontWeight:700, color:CD.muted, letterSpacing:0.8, textTransform:'uppercase', marginBottom:6}}>Todo el día</div>
      <div style={{padding:'10px 12px', background:hexA(CD.red,0.10), border:`1px solid ${hexA(CD.red,0.30)}`, borderRadius:10, display:'flex', alignItems:'center', gap:8, color:CD.red, fontSize:12.5, fontWeight:700}}>
        <span style={{width:6, height:6, borderRadius:'50%', background:CD.red}}/>
        Entrega Cálculo III · 23:59
      </div>
    </div>
  );
}

const HOURS = [8,9,10,11,12,13,14,15,16,17,18,19,20,21,22];
const HOUR_H = 64;

// Timeline events
const TIMELINE = [
  {s:11, e:12.5, l:'Repaso derivadas parciales', sub:'Bloque sugerido por Matix', c:CD.amber, suggested:true},
  {s:14, e:15.5, l:'Cálculo III — Clase', sub:'Aula 4B · Prof. Mendoza', c:CD.accent},
  {s:18, e:19,   l:'Gimnasio', sub:'Personal', c:CD.green},
  {s:20, e:22,   l:'Laboratorio Física II', sub:'Entrega esta noche · urgente', c:CD.red, urgent:true},
];

function Timeline() {
  return (
    <div style={{position:'relative', padding:'0 0 24px'}}>
      {/* hour rows */}
      {HOURS.map((h,i) => (
        <div key={i} style={{display:'flex', height:HOUR_H, position:'relative'}}>
          <div style={{width:54, padding:'0 8px', display:'flex', alignItems:'flex-start', justifyContent:'flex-end', color:CD.muted, fontSize:11, fontWeight:600, paddingTop:0, transform:'translateY(-7px)'}}>
            {h.toString().padStart(2,'0')}:00
          </div>
          <div style={{flex:1, borderTop:`1px solid ${CD.hairline}`, marginRight:12}}/>
        </div>
      ))}

      {/* Events */}
      <div style={{position:'absolute', left:62, right:14, top:0, bottom:0}}>
        {TIMELINE.map((ev,i) => {
          const top = (ev.s - HOURS[0]) * HOUR_H - 7;
          const height = (ev.e - ev.s) * HOUR_H - 8;
          return (
            <div key={i} style={{
              position:'absolute', top, left:0, right:0, height,
              borderRadius:14, overflow:'hidden',
              display:'flex',
            }}>
              <div style={{width:4, background:ev.c, boxShadow:`0 0 12px ${hexA(ev.c,0.45)}`}}/>
              <div style={{
                flex:1, padding:'10px 14px',
                background: ev.urgent ? hexA(CD.red,0.12) : ev.suggested ? hexA(CD.amber,0.10) : CD.card,
                border: ev.urgent ? `1px solid ${hexA(CD.red,0.32)}` : ev.suggested ? `1px dashed ${hexA(CD.amber,0.45)}` : '1px solid rgba(255,255,255,0.03)',
                borderLeft:'none', borderRadius:'0 14px 14px 0',
              }}>
                <div style={{display:'flex', alignItems:'center', gap:8}}>
                  {ev.suggested && (
                    <span style={{display:'inline-flex', alignItems:'center', gap:4, padding:'1px 7px', borderRadius:6, background:hexA(CD.amber,0.20), color:CD.amber, fontSize:9, fontWeight:700, letterSpacing:0.4}}>
                      {ic.spark}<span>MATIX</span>
                    </span>
                  )}
                  {ev.urgent && (
                    <span style={{padding:'1px 7px', borderRadius:6, background:hexA(CD.red,0.20), color:CD.red, fontSize:9, fontWeight:700, letterSpacing:0.4}}>URGENTE</span>
                  )}
                  <span style={{fontSize:10, color:CD.muted, fontWeight:600}}>
                    {ev.s.toFixed(0).padStart(2,'0')}:{((ev.s%1)*60).toString().padStart(2,'0')} — {Math.floor(ev.e).toString().padStart(2,'0')}:{((ev.e%1)*60).toString().padStart(2,'0')}
                  </span>
                </div>
                <div style={{fontSize:14, fontWeight:700, color:CD.text, marginTop:4, letterSpacing:-0.1}}>{ev.l}</div>
                <div style={{fontSize:11.5, color:CD.muted, marginTop:2, fontWeight:500}}>{ev.sub}</div>
              </div>
            </div>
          );
        })}

        {/* now line at 9:45 */}
        <NowLine/>
      </div>
    </div>
  );
}

function NowLine() {
  const top = (9.75 - HOURS[0]) * HOUR_H - 7;
  return (
    <div style={{position:'absolute', top, left:-6, right:0, display:'flex', alignItems:'center', gap:0, pointerEvents:'none', zIndex:2}}>
      <span style={{padding:'2px 7px', borderRadius:6, background:CD.red, color:'#fff', fontSize:9, fontWeight:700, letterSpacing:0.3, transform:'translateX(-100%)', marginLeft:-2, boxShadow:`0 0 10px ${hexA(CD.red,0.6)}`}}>09:45</span>
      <div style={{width:10, height:10, borderRadius:'50%', background:CD.red, marginLeft:-4, boxShadow:`0 0 10px ${CD.red}`}}/>
      <div style={{flex:1, height:2, background:CD.red, boxShadow:`0 0 8px ${hexA(CD.red,0.6)}`}}/>
    </div>
  );
}

function FAB() {
  return (
    <div style={{position:'absolute', right:18, bottom:96, width:60, height:60, borderRadius:'50%', background:CD.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)'}}>{ic.mic}</div>
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
    <div style={{background:CD.bg, borderTop:`1px solid ${CD.hairline}`, padding:'10px 8px 8px', display:'flex', justifyContent:'space-around'}}>
      {items.map(it => (
        <div key={it.key} style={{display:'flex', flexDirection:'column', alignItems:'center', gap:4, flex:1, padding:'4px 0', color:it.active?CD.accent:CD.muted}}>
          {it.active ? <div style={{padding:'4px 14px', borderRadius:999, background:'rgba(45,127,249,0.16)', display:'flex', alignItems:'center', justifyContent:'center'}}>{it.icon}</div> : it.icon}
          <span style={{fontSize:10.5, fontWeight:it.active?600:500}}>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:CD.bg, color:CD.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <Segmented/>
      <MiniStrip/>
      <div style={{flex:1, overflowY:'auto', paddingBottom:96}}>
        <AllDay/>
        <Timeline/>
      </div>
      <MatixFAB/>
      <MatixBottomNav active="home"/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
