// Matix — Nuevo curso

const NC = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF', pink:'#F06EA9', teal:'#3CCFCF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  user: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>,
  pin: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.4"/></svg>,
  cred: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/></svg>,
  chev: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>,
  plus: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>,
};

const COLORS = [NC.accent, NC.green, NC.red, NC.amber, NC.purple, NC.pink, NC.teal];
const SELECTED_COLOR = NC.purple;
const SELECTED_INITIAL = 'F';

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 18px 8px', position:'relative'}}>
      <a href="Universidad.html" style={{width:40, height:40, borderRadius:12, background:NC.card, color:NC.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ic.close}</a>
      <div style={{position:'absolute', left:0, right:0, textAlign:'center', pointerEvents:'none'}}>
        <span style={{fontSize:16, fontWeight:600, color:NC.text, letterSpacing:-0.1}}>Nuevo curso</span>
      </div>
      <div style={{width:40, height:40}}/>
    </div>
  );
}

// Live preview pill
function Preview() {
  return (
    <div style={{padding:'8px 20px 16px', display:'flex', justifyContent:'center'}}>
      <div style={{
        display:'inline-flex', alignItems:'center', gap:14,
        padding:'14px 18px 14px 14px', borderRadius:18,
        background:NC.card, border:`1px solid ${hexA(SELECTED_COLOR,0.30)}`,
        boxShadow:`0 0 24px ${hexA(SELECTED_COLOR,0.16)}`,
      }}>
        <div style={{width:56, height:56, borderRadius:'50%', background:hexA(SELECTED_COLOR,0.16), border:`1.5px solid ${hexA(SELECTED_COLOR,0.55)}`, color:SELECTED_COLOR, display:'flex', alignItems:'center', justifyContent:'center', fontSize:22, fontWeight:700, letterSpacing:-0.5}}>
          {SELECTED_INITIAL}
        </div>
        <div>
          <div style={{fontSize:11, fontWeight:600, color:SELECTED_COLOR, letterSpacing:0.6, textTransform:'uppercase'}}>Vista previa</div>
          <div style={{fontSize:18, fontWeight:700, color:NC.text, letterSpacing:-0.3, marginTop:2}}>Filosofía de la Ciencia</div>
          <div style={{fontSize:11.5, color:NC.muted, marginTop:2, fontWeight:500}}>3 créditos · Vie 18:00</div>
        </div>
      </div>
    </div>
  );
}

function FieldLabel({children}) {
  return <div style={{fontSize:11, fontWeight:600, color:NC.muted, letterSpacing:0.6, textTransform:'uppercase', padding:'12px 22px 6px'}}>{children}</div>;
}

function Input({value, placeholder}) {
  const filled = !!value;
  return (
    <div style={{margin:'0 16px', padding:'14px 14px', background:NC.card, borderRadius:14, border:'1px solid rgba(255,255,255,0.04)', display:'flex', alignItems:'center', gap:10}}>
      <span style={{fontSize:15, fontWeight:filled?600:500, color:filled?NC.text:NC.muted, flex:1}}>
        {value || placeholder}
        {filled && <span style={{display:'inline-block', width:2, height:18, background:NC.accent, marginLeft:2, verticalAlign:'-3px', animation:'blink 1.1s steps(1) infinite'}}/>}
      </span>
    </div>
  );
}

function ColorSwatches() {
  return (
    <div style={{margin:'0 16px', padding:'14px 14px', background:NC.card, borderRadius:14, border:'1px solid rgba(255,255,255,0.04)'}}>
      <div style={{display:'flex', gap:10, flexWrap:'wrap'}}>
        {COLORS.map((c,i) => {
          const sel = c === SELECTED_COLOR;
          return (
            <div key={i} style={{
              width:38, height:38, borderRadius:'50%',
              background: c,
              boxShadow: sel ? `0 0 0 3px ${NC.card}, 0 0 0 5px ${c}, 0 0 14px ${hexA(c,0.5)}` : 'inset 0 0 0 0 transparent',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>
              {sel && (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Weekly schedule grid (small)
const WEEK = ['L','M','X','J','V','S','D'];
const SELECTED_DAYS = [4]; // Friday only
function DaysPicker() {
  return (
    <div style={{margin:'0 16px', padding:'14px 14px', background:NC.card, borderRadius:14, border:'1px solid rgba(255,255,255,0.04)'}}>
      <div style={{display:'flex', gap:6}}>
        {WEEK.map((w,i) => {
          const sel = SELECTED_DAYS.includes(i);
          return (
            <div key={i} style={{
              flex:1, padding:'10px 0', borderRadius:10, textAlign:'center',
              background: sel ? SELECTED_COLOR : 'rgba(255,255,255,0.04)',
              color: sel ? '#fff' : NC.muted,
              fontSize:13, fontWeight:600,
              boxShadow: sel ? `0 4px 14px ${hexA(SELECTED_COLOR,0.35)}` : 'none',
            }}>{w}</div>
          );
        })}
      </div>
      <div style={{display:'flex', alignItems:'center', gap:8, marginTop:12, fontSize:13, fontWeight:500}}>
        <span style={{color:NC.muted}}>Hora</span>
        <div style={{flex:1}}/>
        <span style={{padding:'5px 10px', borderRadius:8, background:'rgba(255,255,255,0.04)', color:NC.text, fontWeight:600}}>18:00</span>
        <span style={{color:NC.muted}}>—</span>
        <span style={{padding:'5px 10px', borderRadius:8, background:'rgba(255,255,255,0.04)', color:NC.text, fontWeight:600}}>20:00</span>
      </div>
    </div>
  );
}

function Row({icon, label, value}) {
  return (
    <div style={{margin:'6px 16px', padding:'12px 14px', background:NC.card, borderRadius:14, border:'1px solid rgba(255,255,255,0.04)', display:'flex', alignItems:'center', gap:12}}>
      <div style={{width:34, height:34, borderRadius:9, background:'rgba(255,255,255,0.04)', color:NC.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:10.5, fontWeight:600, color:NC.muted, letterSpacing:0.5, textTransform:'uppercase'}}>{label}</div>
        <div style={{fontSize:14, fontWeight:500, color:value?NC.text:NC.muted, marginTop:2}}>{value || '—'}</div>
      </div>
      <span style={{color:NC.muted}}>{ic.chev}</span>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:NC.bg, color:NC.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:110}}>
        <Preview/>

        <FieldLabel>Nombre del curso</FieldLabel>
        <Input value="Filosofía de la Ciencia" placeholder=""/>
        <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>

        <FieldLabel>Color</FieldLabel>
        <ColorSwatches/>

        <FieldLabel>Horario</FieldLabel>
        <DaysPicker/>

        <FieldLabel>Detalles</FieldLabel>
        <Row icon={ic.user} label="Profesor" value="Prof. Aguirre"/>
        <Row icon={ic.pin} label="Aula" value="Sala B-12"/>
        <Row icon={ic.cred} label="Créditos" value="3"/>

        <FieldLabel>Sistema de evaluación</FieldLabel>
        <div style={{margin:'0 16px'}}>
          {[
            {n:'Parciales', w:'30%', c:NC.accent},
            {n:'Ensayo final', w:'30%', c:NC.purple},
            {n:'Participación', w:'15%', c:NC.green},
            {n:'Quizzes', w:'25%', c:NC.amber},
          ].map((it,i) => (
            <div key={i} style={{padding:'12px 14px', marginBottom:6, background:NC.card, borderRadius:12, border:'1px solid rgba(255,255,255,0.04)', display:'flex', alignItems:'center', gap:10}}>
              <span style={{width:8, height:8, borderRadius:'50%', background:it.c}}/>
              <span style={{flex:1, fontSize:14, fontWeight:500, color:NC.text}}>{it.n}</span>
              <span style={{padding:'3px 9px', borderRadius:7, background:hexA(it.c,0.14), color:it.c, fontSize:12, fontWeight:700}}>{it.w}</span>
            </div>
          ))}
          <div style={{padding:'12px 14px', marginBottom:6, background:'rgba(255,255,255,0.025)', borderRadius:12, border:`1px dashed ${NC.hairline}`, display:'flex', alignItems:'center', gap:8, color:NC.muted, fontSize:13.5, fontWeight:600}}>
            {ic.plus}<span>Añadir rubro</span>
          </div>
        </div>
      </div>

      <div style={{padding:'12px 16px 18px', background:`linear-gradient(180deg, rgba(11,15,26,0) 0%, ${NC.bg} 30%)`}}>
        <div style={{padding:'15px 0', borderRadius:14, background:SELECTED_COLOR, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', fontSize:15, fontWeight:700, letterSpacing:0.1, boxShadow:`0 12px 28px ${hexA(SELECTED_COLOR,0.40)}, 0 0 0 1px rgba(255,255,255,0.06) inset`}}>
          Crear curso
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
