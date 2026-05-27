// Matix — Estado vacío (Tareas sin nada pendiente)

const EV = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  search: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>,
  plus: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>,
  mic: <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  spark: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  home: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/></svg>,
  tasks: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/></svg>,
  cal: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  uni: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  notes: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 20px 10px'}}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{fontSize:12, color:EV.muted, fontWeight:500}}>Sábado · 23 may</span>
        <span style={{fontSize:26, color:EV.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>Tareas</span>
      </div>
      <div style={{display:'flex', gap:10}}>
        <div style={{width:40, height:40, borderRadius:12, background:EV.card, color:EV.text, display:'flex', alignItems:'center', justifyContent:'center'}}>{ic.search}</div>
        <div style={{width:40, height:40, borderRadius:12, background:EV.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 6px 16px rgba(45,127,249,0.35)'}}>{ic.plus}</div>
      </div>
    </div>
  );
}

function Pills() {
  const tabs = [
    {l:'Hoy', n:0, active:true},
    {l:'Esta semana', n:3},
    {l:'Todas', n:9},
    {l:'Completadas', n:48},
  ];
  return (
    <div style={{display:'flex', gap:8, padding:'8px 20px 14px', overflowX:'auto'}}>
      {tabs.map(t => (
        <div key={t.l} style={{flexShrink:0, display:'flex', alignItems:'center', gap:8, padding:'9px 16px', borderRadius:99, background:t.active?EV.accent:EV.card, color:t.active?'#fff':EV.muted, fontSize:14, fontWeight:t.active?600:500, boxShadow:t.active?'0 4px 14px rgba(45,127,249,0.35)':'none'}}>
          {t.l}
          <span style={{fontSize:11, fontWeight:600, background:t.active?'rgba(255,255,255,0.22)':'rgba(255,255,255,0.05)', color:t.active?'#fff':EV.muted, padding:'2px 7px', borderRadius:999, lineHeight:1}}>{t.n}</span>
        </div>
      ))}
    </div>
  );
}

// Big celebratory illustration
function EmptyIllo() {
  return (
    <div style={{position:'relative', width:200, height:200, display:'flex', alignItems:'center', justifyContent:'center'}}>
      {/* outer rings */}
      <div style={{position:'absolute', inset:0, borderRadius:'50%', background:`radial-gradient(circle, ${hexA(EV.green,0.18)} 0%, transparent 65%)`}}/>
      <div style={{position:'absolute', inset:30, borderRadius:'50%', border:`1px solid ${hexA(EV.green,0.20)}`}}/>
      <div style={{position:'absolute', inset:48, borderRadius:'50%', border:`1.5px solid ${hexA(EV.green,0.35)}`}}/>

      {/* core check */}
      <div style={{
        position:'relative', width:108, height:108, borderRadius:'50%',
        background:`radial-gradient(circle at 30% 30%, ${hexA(EV.green,0.95)} 0%, ${EV.green} 50%, ${hexA(EV.green,0.65)} 100%)`,
        boxShadow:`0 20px 60px ${hexA(EV.green,0.55)}, 0 0 0 6px ${hexA(EV.green,0.14)}, inset 0 -8px 20px rgba(0,0,0,0.20)`,
        display:'flex', alignItems:'center', justifyContent:'center',
        color:'#0B0F1A',
      }}>
        <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>
      </div>

      {/* sparkles */}
      <div style={{position:'absolute', top:18, right:24, width:6, height:6, borderRadius:'50%', background:EV.amber, boxShadow:`0 0 10px ${EV.amber}`}}/>
      <div style={{position:'absolute', bottom:24, left:24, width:5, height:5, borderRadius:'50%', background:EV.accent, boxShadow:`0 0 10px ${EV.accent}`}}/>
      <div style={{position:'absolute', top:48, left:18, width:4, height:4, borderRadius:'50%', background:EV.purple, boxShadow:`0 0 8px ${EV.purple}`}}/>
    </div>
  );
}

function Hint({l, accent}) {
  return (
    <div style={{padding:'8px 14px', borderRadius:99, background:accent?hexA(EV.accent,0.14):EV.card, border:accent?`1px solid ${hexA(EV.accent,0.30)}`:'1px solid rgba(255,255,255,0.04)', color:accent?EV.accent:EV.muted, fontSize:12.5, fontWeight:600, whiteSpace:'nowrap'}}>
      {l}
    </div>
  );
}

function FAB() {
  return (
    <div style={{position:'absolute', right:18, bottom:96, width:60, height:60, borderRadius:'50%', background:EV.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)'}}>{ic.mic}</div>
  );
}

function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ic.home},
    {key:'tasks', label:'Tareas', icon:ic.tasks, active:true},
    {key:'cal', label:'Calendario', icon:ic.cal},
    {key:'uni', label:'Universidad', icon:ic.uni},
    {key:'notes', label:'Apuntes', icon:ic.notes},
  ];
  return (
    <div style={{background:EV.bg, borderTop:`1px solid ${EV.hairline}`, padding:'10px 8px 8px', display:'flex', justifyContent:'space-around'}}>
      {items.map(it => (
        <div key={it.key} style={{display:'flex', flexDirection:'column', alignItems:'center', gap:4, flex:1, padding:'4px 0', color:it.active?EV.accent:EV.muted}}>
          {it.active ? <div style={{padding:'4px 14px', borderRadius:999, background:'rgba(45,127,249,0.16)', display:'flex', alignItems:'center', justifyContent:'center'}}>{it.icon}</div> : it.icon}
          <span style={{fontSize:10.5, fontWeight:it.active?600:500}}>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:EV.bg, color:EV.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <Pills/>

      <div style={{flex:1, padding:'24px 22px 120px', display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', textAlign:'center', overflowY:'auto'}}>
        <EmptyIllo/>

        <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'3px 10px', borderRadius:99, background:hexA(EV.green,0.14), border:`1px solid ${hexA(EV.green,0.32)}`, color:EV.green, fontSize:10.5, fontWeight:700, letterSpacing:1.2, marginTop:16}}>
          <span style={{width:6, height:6, borderRadius:'50%', background:EV.green, boxShadow:`0 0 6px ${EV.green}`}}/>
          <span>TODO AL DÍA</span>
        </div>

        <h2 style={{margin:'14px 0 0', fontSize:22, fontWeight:700, color:EV.text, letterSpacing:-0.5, lineHeight:1.2, textWrap:'balance'}}>
          No tienes nada pendiente para hoy
        </h2>
        <p style={{margin:'10px 24px 0', fontSize:14, color:EV.muted, lineHeight:1.55, fontWeight:500, textWrap:'pretty', maxWidth:320}}>
          Perfecto momento para adelantar el repaso del examen de Cálculo, o tomarte una pausa.
        </p>

        {/* Matix nudge */}
        <div style={{marginTop:20, padding:'12px 14px', background:EV.card, borderRadius:14, border:`1px solid ${hexA(EV.accent,0.32)}`, maxWidth:320, position:'relative', overflow:'hidden'}}>
          <div style={{position:'absolute', top:-30, right:-20, width:120, height:120, background:`radial-gradient(circle, ${hexA(EV.accent,0.14)} 0%, transparent 70%)`}}/>
          <div style={{position:'relative', display:'flex', alignItems:'flex-start', gap:10, textAlign:'left'}}>
            <div style={{width:28, height:28, borderRadius:'50%', background:hexA(EV.accent,0.16), border:`1.2px solid ${EV.accent}`, color:EV.accent, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
              {ic.spark}
            </div>
            <div style={{flex:1}}>
              <div style={{fontSize:10.5, fontWeight:700, color:EV.accent, letterSpacing:0.8, textTransform:'uppercase'}}>Sugerencia de Matix</div>
              <div style={{fontSize:13, color:EV.text, marginTop:4, lineHeight:1.5, fontWeight:500}}>
                «Te puedo armar un bloque de repaso de 1 h para el examen del viernes.»
              </div>
            </div>
          </div>
        </div>

        <div style={{display:'flex', gap:8, marginTop:18, flexWrap:'wrap', justifyContent:'center'}}>
          <Hint l="+ Crear tarea" accent/>
          <Hint l="Pregunta a Matix"/>
          <Hint l="Ver semana"/>
        </div>
      </div>

      <MatixFAB/>
      <MatixBottomNav active="tasks"/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
