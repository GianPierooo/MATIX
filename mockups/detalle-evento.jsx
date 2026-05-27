// Matix — Detalle de evento

const DE = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const EV = DE.accent;
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ev = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  edit: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M16 4l4 4-12 12H4v-4z"/><path d="M13 7l4 4"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  cal: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  clock: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>,
  pin: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.4"/></svg>,
  bell: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2H4.5z"/><path d="M10.5 21h3"/></svg>,
  rep: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12a8 8 0 0 1 14-5.3L20 9"/><path d="M20 5v4h-4"/><path d="M20 12a8 8 0 0 1-14 5.3L4 15"/><path d="M4 19v-4h4"/></svg>,
  spark: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  trash: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M5 7h14"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h7a1.5 1.5 0 0 0 1.5-1.5L18 7"/><path d="M9 7V4.5h6V7"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
      <a href="Calendario.html" style={{width:40, height:40, borderRadius:12, background:DE.card, color:DE.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ev.back}</a>
      <div style={{display:'flex', gap:8}}>
        <div style={{width:40, height:40, borderRadius:12, background:DE.card, color:DE.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ev.edit}</div>
        <div style={{width:40, height:40, borderRadius:12, background:DE.card, color:DE.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ev.more}</div>
      </div>
    </div>
  );
}

function Hero() {
  return (
    <div style={{padding:'12px 20px 16px', position:'relative'}}>
      {/* category strip */}
      <div style={{display:'flex', alignItems:'center', gap:10, marginBottom:14}}>
        <span style={{width:10, height:10, borderRadius:'50%', background:EV, boxShadow:`0 0 12px ${hexA(EV,0.6)}`}}/>
        <span style={{fontSize:11, fontWeight:700, color:EV, letterSpacing:0.6, textTransform:'uppercase'}}>Clase · Cálculo III</span>
      </div>
      <div style={{fontSize:26, fontWeight:700, color:DE.text, letterSpacing:-0.6, lineHeight:1.15}}>
        Cálculo III — Derivadas direccionales
      </div>
      <div style={{marginTop:10, fontSize:14, color:DE.muted, fontWeight:500, lineHeight:1.5}}>
        Clase regular semanal, con Prof. Mendoza.
      </div>

      {/* Time block */}
      <div style={{marginTop:16, padding:'16px', background:DE.card, borderRadius:18, border:'1px solid rgba(255,255,255,0.03)', display:'flex', alignItems:'center', gap:14}}>
        <div style={{flex:'0 0 auto', width:56, height:62, borderRadius:14, background:hexA(EV,0.14), border:`1px solid ${hexA(EV,0.35)}`, color:EV, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center'}}>
          <span style={{fontSize:10, fontWeight:600, letterSpacing:0.6, textTransform:'uppercase'}}>SÁB</span>
          <span style={{fontSize:22, fontWeight:700, letterSpacing:-0.6, marginTop:1}}>23</span>
        </div>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize:15, fontWeight:700, color:DE.text, letterSpacing:-0.2}}>14:00 — 15:30</div>
          <div style={{fontSize:12.5, color:DE.muted, marginTop:3, fontWeight:500}}>Mayo 2026 · 90 minutos</div>
        </div>
        <span style={{padding:'4px 10px', borderRadius:99, background:hexA(DE.amber,0.14), border:`1px solid ${hexA(DE.amber,0.35)}`, color:DE.amber, fontSize:11.5, fontWeight:700, whiteSpace:'nowrap'}}>en 4 h 20 min</span>
      </div>
    </div>
  );
}

function Row({icon, label, value, sub}) {
  return (
    <div style={{display:'flex', alignItems:'flex-start', gap:14, padding:'14px 18px', borderBottom:`1px solid ${DE.hairline}`}}>
      <div style={{width:32, height:32, borderRadius:9, background:'rgba(255,255,255,0.04)', color:DE.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:11, fontWeight:600, color:DE.muted, letterSpacing:0.6, textTransform:'uppercase'}}>{label}</div>
        <div style={{fontSize:14, fontWeight:600, color:DE.text, marginTop:3, letterSpacing:-0.1}}>{value}</div>
        {sub && <div style={{fontSize:12, color:DE.muted, marginTop:3, fontWeight:500}}>{sub}</div>}
      </div>
    </div>
  );
}

function SectionLabel({children}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:8, padding:'18px 22px 8px'}}>
      <span style={{fontSize:11, fontWeight:600, color:DE.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{children}</span>
      <div style={{flex:1, height:1, background:DE.hairline}}/>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:DE.bg, color:DE.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:120}}>
        <Hero/>

        <div style={{margin:'4px 16px 0', background:DE.card, borderRadius:18, overflow:'hidden'}}>
          <Row icon={ev.pin} label="Ubicación" value="Aula 4B" sub="Pabellón de Ciencias, 2º piso"/>
          <Row icon={ev.bell} label="Recordatorio" value="15 minutos antes" sub="Notificación con sonido"/>
          <Row icon={ev.rep} label="Repetición" value="Lun y Mié · 14:00" sub="Hasta el 26 de junio"/>
        </div>

        <SectionLabel>Tareas asociadas · 2</SectionLabel>
        <div style={{padding:'0 16px', display:'flex', flexDirection:'column', gap:8}}>
          {[
            {t:'Repasar derivadas parciales', m:'Antes de la clase · 11:00', c:DE.amber, done:false},
            {t:'Llevar problemario impreso', m:'Antes de la clase · 13:00', c:DE.accent, done:true},
          ].map((it,i) => (
            <div key={i} style={{display:'flex', alignItems:'center', gap:12, padding:'12px 12px', background:DE.card, borderRadius:12}}>
              <div style={{width:20, height:20, borderRadius:'50%', background:it.done?DE.green:'transparent', border:it.done?'none':'1.6px solid rgba(255,255,255,0.22)', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
                {it.done && <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>}
              </div>
              <div style={{flex:1, minWidth:0}}>
                <div style={{display:'flex', alignItems:'center', gap:8}}>
                  <span style={{width:6, height:6, borderRadius:'50%', background:it.c}}/>
                  <span style={{fontSize:13.5, fontWeight:600, color:it.done?DE.muted:DE.text, textDecoration:it.done?'line-through':'none'}}>{it.t}</span>
                </div>
                <div style={{fontSize:11.5, color:DE.muted, marginTop:3, fontWeight:500}}>{it.m}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Matix */}
        <div style={{margin:'18px 16px 0', padding:'14px 14px', background:DE.card, borderRadius:16, border:`1px solid ${hexA(DE.accent,0.35)}`, position:'relative', overflow:'hidden'}}>
          <div style={{position:'absolute', top:-30, right:-20, width:120, height:120, background:`radial-gradient(circle, ${hexA(DE.accent,0.16)} 0%, transparent 70%)`}}/>
          <div style={{position:'relative'}}>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'3px 9px 3px 8px', borderRadius:99, background:hexA(DE.accent,0.16), color:DE.accent, fontSize:10.5, fontWeight:700, letterSpacing:1.2}}>
              {ev.spark}<span>MATIX</span>
            </div>
            <div style={{marginTop:9, fontSize:13.5, color:DE.text, lineHeight:1.5, fontWeight:500}}>
              Tienes 4 h antes de la clase. Te sugiero <span style={{color:DE.accent, fontWeight:700}}>terminar el repaso de derivadas parciales</span> entre las 11:00 y las 12:30.
            </div>
          </div>
        </div>

        <SectionLabel>Acciones</SectionLabel>
        <div style={{padding:'0 16px', display:'flex', flexDirection:'column', gap:6}}>
          <a href="Modal%20Borrar.html" style={{padding:'13px 14px', background:DE.card, borderRadius:12, fontSize:14, color:DE.red, fontWeight:600, display:'flex', alignItems:'center', gap:10, textDecoration:'none'}}>
            {ev.trash}<span>Eliminar evento</span>
          </a>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
