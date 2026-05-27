// Matix — Nuevo evento

const NE = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const i = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  cal: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  clock: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>,
  pin: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.4"/></svg>,
  bell: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2H4.5z"/><path d="M10.5 21h3"/></svg>,
  rep: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12a8 8 0 0 1 14-5.3L20 9"/><path d="M20 5v4h-4"/><path d="M20 12a8 8 0 0 1-14 5.3L4 15"/><path d="M4 19v-4h4"/></svg>,
  tag: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12V4a1 1 0 0 1 1-1h8l9 9-9 9z"/><circle cx="8" cy="8" r="1.5"/></svg>,
  chev: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 18px 8px', position:'relative'}}>
      <a href="Calendario.html" style={{width:40, height:40, borderRadius:12, background:NE.card, color:NE.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{i.close}</a>
      <div style={{position:'absolute', left:0, right:0, textAlign:'center', pointerEvents:'none'}}>
        <span style={{fontSize:16, fontWeight:600, color:NE.text, letterSpacing:-0.1}}>Nuevo evento</span>
      </div>
      <div style={{width:40, height:40}}/>
    </div>
  );
}

function Title() {
  return (
    <div style={{padding:'14px 22px 18px'}}>
      <div style={{fontSize:22, fontWeight:600, letterSpacing:-0.5, color:NE.text, lineHeight:1.25}}>
        <span>Cálculo III — Clase</span>
        <span style={{display:'inline-block', width:2, height:24, background:NE.accent, marginLeft:2, verticalAlign:'-4px', animation:'blink 1.1s steps(1) infinite'}}/>
      </div>
      <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>
      <div style={{marginTop:4, fontSize:13, color:NE.muted}}>¿Qué quieres agendar?</div>
    </div>
  );
}

// Day-long toggle row
function ToggleRow({label, on}) {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 18px', borderBottom:`1px solid ${NE.hairline}`}}>
      <span style={{fontSize:14, fontWeight:500, color:NE.text}}>{label}</span>
      <div style={{width:42, height:24, borderRadius:99, background:on?NE.accent:'rgba(255,255,255,0.08)', position:'relative', boxShadow: on?`0 0 0 1px ${hexA(NE.accent,0.4)}`:'none', transition:'all 0.2s'}}>
        <div style={{position:'absolute', top:2, left:on?20:2, width:20, height:20, borderRadius:'50%', background:'#fff', boxShadow:'0 2px 6px rgba(0,0,0,0.3)', transition:'all 0.2s'}}/>
      </div>
    </div>
  );
}

function Row({icon, label, value, last, accent}) {
  return (
    <div style={{display:'flex', alignItems:'flex-start', gap:14, padding:'14px 18px', borderBottom: last?'none':`1px solid ${NE.hairline}`}}>
      <div style={{width:36, height:36, borderRadius:10, background:accent?hexA(NE.accent,0.14):'rgba(255,255,255,0.04)', color:accent?NE.accent:NE.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>
      <div style={{flex:1, minWidth:0, paddingTop:2}}>
        <div style={{fontSize:11, fontWeight:600, color:NE.muted, letterSpacing:0.6, textTransform:'uppercase'}}>{label}</div>
        <div style={{display:'flex', alignItems:'center', gap:8, marginTop:6}}>
          <span style={{flex:1, fontSize:15, fontWeight:500, color:NE.text}}>{value}</span>
          <span style={{color:NE.muted}}>{i.chev}</span>
        </div>
      </div>
    </div>
  );
}

// Time inputs side by side
function TimeRange() {
  return (
    <div style={{display:'flex', alignItems:'flex-start', gap:14, padding:'14px 18px', borderBottom:`1px solid ${NE.hairline}`}}>
      <div style={{width:36, height:36, borderRadius:10, background:'rgba(255,255,255,0.04)', color:NE.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{i.clock}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:11, fontWeight:600, color:NE.muted, letterSpacing:0.6, textTransform:'uppercase'}}>Hora</div>
        <div style={{display:'flex', gap:8, marginTop:6}}>
          <div style={{flex:1, padding:'10px 12px', borderRadius:10, background:'rgba(255,255,255,0.04)', display:'flex', alignItems:'center', justifyContent:'space-between'}}>
            <span style={{fontSize:14, fontWeight:600, color:NE.text}}>14:00</span>
            <span style={{fontSize:10, color:NE.muted, fontWeight:600}}>INICIO</span>
          </div>
          <div style={{flex:1, padding:'10px 12px', borderRadius:10, background:'rgba(255,255,255,0.04)', display:'flex', alignItems:'center', justifyContent:'space-between'}}>
            <span style={{fontSize:14, fontWeight:600, color:NE.text}}>15:30</span>
            <span style={{fontSize:10, color:NE.muted, fontWeight:600}}>FIN</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// Color swatches
function ColorPicker() {
  const colors = [
    {c:NE.accent, label:'Clase'},
    {c:NE.green, label:'Personal'},
    {c:NE.red, label:'Entrega'},
    {c:NE.amber, label:'Examen'},
    {c:NE.purple, label:'Otro'},
  ];
  return (
    <div style={{padding:'14px 18px', borderBottom:`1px solid ${NE.hairline}`}}>
      <div style={{fontSize:11, fontWeight:600, color:NE.muted, letterSpacing:0.6, textTransform:'uppercase', marginBottom:10}}>Categoría</div>
      <div style={{display:'flex', gap:8, overflowX:'auto'}}>
        {colors.map((co,idx) => {
          const sel = idx === 0;
          return (
            <div key={idx} style={{flexShrink:0, display:'flex', flexDirection:'column', alignItems:'center', gap:6}}>
              <div style={{
                width:44, height:44, borderRadius:14,
                background: hexA(co.c, sel?0.22:0.10),
                border: sel ? `2px solid ${co.c}` : `1px solid ${hexA(co.c,0.30)}`,
                display:'flex', alignItems:'center', justifyContent:'center',
                boxShadow: sel ? `0 0 20px ${hexA(co.c,0.40)}` : 'none',
              }}>
                <span style={{width:14, height:14, borderRadius:'50%', background:co.c}}/>
              </div>
              <span style={{fontSize:10.5, color:sel?co.c:NE.muted, fontWeight:sel?700:500, letterSpacing:0.1}}>{co.label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:NE.bg, color:NE.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:110}}>
        <Title/>

        <div style={{margin:'4px 16px 0', background:NE.card, borderRadius:18, overflow:'hidden'}}>
          <ToggleRow label="Todo el día" on={false}/>
          <Row icon={i.cal} label="Fecha" value="Sábado 23 de mayo" accent/>
          <TimeRange/>
          <Row icon={i.pin} label="Ubicación" value="Aula 4B, Pabellón de Ciencias"/>
          <ColorPicker/>
          <Row icon={i.rep} label="Repetición" value="Lun y Mié · semanal"/>
          <Row icon={i.bell} label="Recordatorio" value="15 min antes" last/>
        </div>

        {/* Notas */}
        <div style={{margin:'14px 16px 0', background:NE.card, borderRadius:18, padding:'14px 14px'}}>
          <div style={{fontSize:11, fontWeight:600, color:NE.muted, letterSpacing:0.6, textTransform:'uppercase'}}>Nota</div>
          <div style={{marginTop:8, padding:'10px 12px', background:'rgba(255,255,255,0.03)', border:`1px solid ${NE.hairline}`, borderRadius:12, color:NE.muted, fontSize:14, lineHeight:1.5, minHeight:54}}>
            Llevar problemario impreso y resumen de derivadas parciales…
          </div>
        </div>
      </div>

      <div style={{padding:'12px 16px 18px', background:`linear-gradient(180deg, rgba(11,15,26,0) 0%, ${NE.bg} 30%)`}}>
        <div style={{padding:'15px 0', borderRadius:14, background:NE.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', fontSize:15, fontWeight:700, letterSpacing:0.1, boxShadow:'0 12px 28px rgba(45,127,249,0.40), 0 0 0 1px rgba(255,255,255,0.06) inset'}}>
          Guardar evento
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
