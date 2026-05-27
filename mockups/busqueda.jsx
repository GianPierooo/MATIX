// Matix — Búsqueda global

const SR = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  x: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  search: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>,
  spark: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  mic: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  task: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/></svg>,
  cal: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  note: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
  uni: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  hist: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12a8 8 0 1 0 2.3-5.7L4 9"/><path d="M4 4v5h5"/><path d="M12 8v4l3 2"/></svg>,
  ar: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M7 17 17 7"/><path d="M9 7h8v8"/></svg>,
};

const QUERY = 'gradiente';

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', gap:10, padding:'14px 16px 10px'}}>
      <a href="Inicio.html" style={{width:40, height:40, borderRadius:12, background:SR.card, color:SR.text, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, textDecoration:'none'}}>{ic.back}</a>
      <div style={{flex:1, height:44, padding:'0 14px', background:SR.card, borderRadius:14, display:'flex', alignItems:'center', gap:10, border:`1px solid ${hexA(SR.accent,0.25)}`}}>
        <span style={{color:SR.accent}}>{ic.search}</span>
        <div style={{flex:1, display:'flex', alignItems:'center', minWidth:0}}>
          <span style={{fontSize:15, fontWeight:600, color:SR.text}}>{QUERY}</span>
          <span style={{display:'inline-block', width:2, height:18, background:SR.accent, marginLeft:2, animation:'blink 1.1s steps(1) infinite'}}/>
        </div>
        <div style={{width:22, height:22, borderRadius:'50%', background:'rgba(255,255,255,0.06)', color:SR.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{ic.x}</div>
      </div>
      <div style={{width:40, height:40, borderRadius:12, background:SR.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, boxShadow:'0 6px 16px rgba(45,127,249,0.35)'}}>{ic.mic}</div>
      <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>
    </div>
  );
}

function Chips({active}) {
  const tabs = [
    {l:'Todo', n:18, active:true},
    {l:'Tareas', n:4},
    {l:'Eventos', n:1},
    {l:'Apuntes', n:9},
    {l:'Cursos', n:1},
  ];
  return (
    <div style={{display:'flex', gap:8, padding:'4px 16px 8px', overflowX:'auto'}}>
      {tabs.map(t => (
        <div key={t.l} style={{flexShrink:0, display:'flex', alignItems:'center', gap:6, padding:'7px 12px', borderRadius:99, background:t.active?SR.accent:SR.card, color:t.active?'#fff':SR.muted, fontSize:12.5, fontWeight:t.active?600:500, boxShadow:t.active?'0 4px 14px rgba(45,127,249,0.30)':'none'}}>
          {t.l}
          <span style={{padding:'1px 6px', borderRadius:99, background:t.active?'rgba(255,255,255,0.22)':'rgba(255,255,255,0.05)', fontSize:10, fontWeight:700}}>{t.n}</span>
        </div>
      ))}
    </div>
  );
}

function SectionLabel({children, count}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:8, padding:'14px 22px 6px'}}>
      <span style={{fontSize:11, fontWeight:600, color:SR.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{children}</span>
      {count!==undefined && <span style={{fontSize:11, color:SR.muted, opacity:0.6, fontWeight:600}}>{count}</span>}
      <div style={{flex:1, height:1, background:SR.hairline}}/>
    </div>
  );
}

function Hit({icon, kind, kindColor, title, snippet, meta}) {
  // Replace `gradiente` with highlight
  const renderHL = (text) => {
    const parts = text.split(/(gradiente)/gi);
    return parts.map((p,i) => p.toLowerCase()==='gradiente'
      ? <mark key={i} style={{background:hexA(SR.accent,0.22), color:SR.accent, padding:'0 2px', borderRadius:3, fontWeight:700}}>{p}</mark>
      : <span key={i}>{p}</span>
    );
  };
  return (
    <div style={{margin:'4px 16px', padding:'12px 14px', background:SR.card, borderRadius:14, border:'1px solid rgba(255,255,255,0.03)', display:'flex', alignItems:'flex-start', gap:12}}>
      <div style={{width:34, height:34, borderRadius:10, background:hexA(kindColor,0.14), border:`1px solid ${hexA(kindColor,0.30)}`, color:kindColor, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'center', gap:8}}>
          <span style={{fontSize:10, fontWeight:700, color:kindColor, letterSpacing:0.6, textTransform:'uppercase'}}>{kind}</span>
          <span style={{fontSize:10, color:SR.muted, fontWeight:500}}>· {meta}</span>
        </div>
        <div style={{fontSize:14.5, fontWeight:600, color:SR.text, marginTop:3, letterSpacing:-0.1, lineHeight:1.25}}>{renderHL(title)}</div>
        {snippet && <div style={{fontSize:12.5, color:SR.muted, marginTop:5, lineHeight:1.45, fontWeight:500}}>{renderHL(snippet)}</div>}
      </div>
      <span style={{color:SR.muted, marginTop:2}}>{ic.ar}</span>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:SR.bg, color:SR.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <Chips/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:30}}>
        {/* Matix answer */}
        <div style={{margin:'8px 16px 6px', padding:'14px 14px', background:SR.card, borderRadius:16, border:`1px solid ${hexA(SR.accent,0.35)}`, position:'relative', overflow:'hidden'}}>
          <div style={{position:'absolute', top:-30, right:-20, width:120, height:120, background:`radial-gradient(circle, ${hexA(SR.accent,0.14)} 0%, transparent 70%)`}}/>
          <div style={{position:'relative'}}>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'3px 9px 3px 8px', borderRadius:99, background:hexA(SR.accent,0.16), color:SR.accent, fontSize:10.5, fontWeight:700, letterSpacing:1.2}}>
              {ic.spark}<span>RESPUESTA MATIX</span>
            </div>
            <div style={{marginTop:9, fontSize:13.5, color:SR.text, lineHeight:1.55, fontWeight:500}}>
              Encontré <b>18 referencias</b> a <i>gradiente</i> en tus apuntes y tareas. Los conceptos clave están en <span style={{color:SR.accent, fontWeight:700}}>Cálculo III · Clase 12</span> y la entrega del capítulo 7.
            </div>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, marginTop:10, padding:'6px 11px', borderRadius:9, background:hexA(SR.accent,0.14), border:`1px solid ${hexA(SR.accent,0.32)}`, color:SR.accent, fontSize:12, fontWeight:700}}>
              Resumir todo
            </div>
          </div>
        </div>

        <SectionLabel count="2">Tareas · 2</SectionLabel>
        <Hit icon={ic.task} kind="Tarea" kindColor={SR.red}
          title="Resolver problemario del capítulo 7 — derivadas y gradiente"
          snippet="Vence hoy 23:59. Cálculo III · Prof. Mendoza."
          meta="Hoy"/>
        <Hit icon={ic.task} kind="Tarea" kindColor={SR.amber}
          title="Trabajo grupal — Aplicaciones del gradiente"
          snippet="Borrador de tres páginas con dos ejemplos concretos."
          meta="Mar 26"/>

        <SectionLabel count="3">Apuntes · 3</SectionLabel>
        <Hit icon={ic.note} kind="Apunte" kindColor={SR.accent}
          title="Clase 12 — gradiente y campo vectorial"
          snippet="«El gradiente apunta en la dirección de máximo crecimiento de f, y su norma es el valor máximo de la derivada direccional…»"
          meta="Cálculo III · hoy"/>
        <Hit icon={ic.note} kind="Apunte" kindColor={SR.green}
          title="Ley de Gauss"
          snippet="…el flujo del campo se relaciona con la divergencia, y la divergencia con el gradiente de un potencial."
          meta="Física II · ayer"/>
        <Hit icon={ic.note} kind="Apunte" kindColor={SR.accent}
          title="Integrales múltiples — resumen"
          snippet="…el Jacobiano controla el cambio de variables; ver también gradiente."
          meta="Cálculo III · 21 may"/>

        <SectionLabel count="1">Eventos · 1</SectionLabel>
        <Hit icon={ic.cal} kind="Evento" kindColor={SR.accent}
          title="Cálculo III — Clase de derivadas direccionales y gradiente"
          snippet="Sábado 14:00 — 15:30 · Aula 4B"
          meta="Hoy"/>

        <SectionLabel count="1">Cursos · 1</SectionLabel>
        <Hit icon={ic.uni} kind="Curso" kindColor={SR.accent}
          title="Cálculo III"
          snippet="9 menciones de gradiente · Prof. Mendoza"
          meta="Activo"/>

        {/* Recent searches */}
        <SectionLabel>Búsquedas recientes</SectionLabel>
        <div style={{padding:'0 16px 12px', display:'flex', gap:8, flexWrap:'wrap'}}>
          {['Jacobiano', 'examen viernes', 'lab física', 'derivadas parciales', 'Aguirre'].map((q,i) => (
            <div key={i} style={{display:'flex', alignItems:'center', gap:6, padding:'7px 11px 7px 10px', borderRadius:99, background:SR.card, color:SR.muted, fontSize:12, fontWeight:500}}>
              {ic.hist}<span>{q}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
