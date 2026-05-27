// Matix — Selector de fecha y hora (bottom sheet)

const SF = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

// Faded "Nueva tarea" form behind sheet
function BgScreen() {
  return (
    <div style={{position:'absolute', inset:0, background:SF.bg, opacity:0.55, pointerEvents:'none'}}>
      <div style={{padding:'14px 18px 8px', display:'flex', justifyContent:'space-between'}}>
        <div style={{width:40, height:40, borderRadius:12, background:SF.card}}/>
        <div style={{width:100, height:18, background:SF.card, borderRadius:6, alignSelf:'center'}}/>
        <div style={{width:40, height:40}}/>
      </div>
      <div style={{padding:'14px 22px'}}>
        <div style={{height:28, width:'70%', background:SF.card, borderRadius:8}}/>
      </div>
      <div style={{margin:'10px 16px', padding:16, background:SF.card, borderRadius:18}}>
        {[1,2,3,4].map(i=>(
          <div key={i} style={{padding:'14px 0', borderBottom:i<4?`1px solid ${SF.hairline}`:'none', display:'flex', gap:10}}>
            <div style={{width:36, height:36, borderRadius:10, background:'rgba(255,255,255,0.04)'}}/>
            <div style={{flex:1}}>
              <div style={{height:10, width:'40%', background:'rgba(255,255,255,0.04)', borderRadius:5}}/>
              <div style={{height:14, marginTop:6, width:'60%', background:'rgba(255,255,255,0.04)', borderRadius:6}}/>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Scrim() {
  return <div style={{position:'absolute', inset:0, background:'rgba(0,0,0,0.55)', backdropFilter:'blur(2px)'}}/>;
}

const WEEKDAYS = ['L','M','X','J','V','S','D'];
const SEL = 30; // selected day in May
const TODAY = 23;

// May 2026, May 1 = Friday → 4 leading prev days
function buildCells() {
  const cells = [];
  for (let i = 0; i < 4; i++) cells.push({d: 27+i, muted:true});
  for (let d = 1; d <= 31; d++) cells.push({d});
  let n = 1;
  while (cells.length % 7 !== 0) cells.push({d: n++, muted:true});
  while (cells.length < 42) cells.push({d: n++, muted:true});
  return cells;
}

function MiniCalendar() {
  const cells = buildCells();
  return (
    <div>
      <div style={{display:'grid', gridTemplateColumns:'repeat(7, 1fr)', padding:'0 14px 6px'}}>
        {WEEKDAYS.map((w,i) => (
          <div key={i} style={{textAlign:'center', fontSize:10.5, fontWeight:700, color:i>=5?hexA(SF.muted,0.7):SF.muted, letterSpacing:0.6}}>{w}</div>
        ))}
      </div>
      <div style={{display:'grid', gridTemplateColumns:'repeat(7, 1fr)', gap:2, padding:'0 10px'}}>
        {cells.map((c,idx) => {
          const isSel = !c.muted && c.d === SEL;
          const isToday = !c.muted && c.d === TODAY;
          return (
            <div key={idx} style={{aspectRatio:'1 / 1', display:'flex', alignItems:'center', justifyContent:'center'}}>
              <div style={{
                width:34, height:34, borderRadius:'50%',
                background: isSel?SF.accent:'transparent',
                border: isToday && !isSel ? `1.5px solid ${hexA(SF.accent,0.55)}` : 'none',
                color: isSel?'#fff': c.muted?hexA(SF.muted,0.45):SF.text,
                display:'flex', alignItems:'center', justifyContent:'center',
                fontSize:13, fontWeight: isSel?700:500,
                boxShadow: isSel ? `0 6px 14px ${hexA(SF.accent,0.45)}` : 'none',
              }}>{c.d}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Wheel-style time picker
function Wheel({values, selectedIndex}) {
  // show 5 values centered on selected
  const shown = [];
  for (let off=-2; off<=2; off++) {
    const idx = (selectedIndex + off + values.length) % values.length;
    shown.push({v: values[idx], off});
  }
  return (
    <div style={{flex:1, position:'relative', height:160, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center'}}>
      {/* selected band */}
      <div style={{position:'absolute', left:0, right:0, top:'50%', transform:'translateY(-50%)', height:34, background:hexA(SF.accent,0.10), borderRadius:10, border:`1px solid ${hexA(SF.accent,0.30)}`}}/>
      <div style={{position:'relative', display:'flex', flexDirection:'column', alignItems:'center', gap:6}}>
        {shown.map((s,i) => {
          const opacity = s.off === 0 ? 1 : Math.abs(s.off) === 1 ? 0.5 : 0.2;
          const fontSize = s.off === 0 ? 22 : 16;
          const fontWeight = s.off === 0 ? 700 : 500;
          const color = s.off === 0 ? SF.accent : SF.text;
          return (
            <div key={i} style={{fontSize, fontWeight, color, opacity, letterSpacing:-0.3, fontVariantNumeric:'tabular-nums'}}>
              {s.v}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Sheet() {
  const hours = Array.from({length:24}, (_,i) => i.toString().padStart(2,'0'));
  const mins = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];
  return (
    <div style={{
      position:'absolute', left:0, right:0, bottom:0,
      background:SF.bg, borderTopLeftRadius:24, borderTopRightRadius:24,
      borderTop:`1px solid ${SF.hairline}`,
      paddingBottom:18,
      display:'flex', flexDirection:'column',
      boxShadow:'0 -20px 60px rgba(0,0,0,0.5)',
      maxHeight:'90%',
    }}>
      <div style={{display:'flex', justifyContent:'center', padding:'10px 0 4px'}}>
        <div style={{width:48, height:5, borderRadius:99, background:'rgba(255,255,255,0.18)'}}/>
      </div>

      <div style={{padding:'4px 22px 6px'}}>
        <div style={{fontSize:11, fontWeight:700, color:SF.muted, letterSpacing:0.8, textTransform:'uppercase'}}>Fecha y hora</div>
        <div style={{fontSize:24, fontWeight:700, color:SF.text, letterSpacing:-0.5, marginTop:2}}>
          Vie <span style={{color:SF.accent}}>30</span> mayo · <span style={{color:SF.accent}}>23 : 59</span>
        </div>
      </div>

      {/* Month switcher */}
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'10px 22px 8px'}}>
        <span style={{fontSize:15, fontWeight:700, color:SF.text}}>Mayo 2026</span>
        <div style={{display:'flex', gap:6}}>
          <div style={{width:28, height:28, borderRadius:8, background:'rgba(255,255,255,0.04)', color:SF.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
          </div>
          <div style={{width:28, height:28, borderRadius:8, background:'rgba(255,255,255,0.04)', color:SF.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>
          </div>
        </div>
      </div>

      <MiniCalendar/>

      {/* Quick chips */}
      <div style={{display:'flex', gap:6, padding:'12px 16px 6px', overflowX:'auto'}}>
        {['Hoy','Mañana','En 3 días','Próximo viernes','Sin fecha'].map((l,i) => (
          <div key={i} style={{flexShrink:0, padding:'6px 11px', borderRadius:99, background:SF.card, color:SF.muted, fontSize:12, fontWeight:500, border:'1px solid rgba(255,255,255,0.04)'}}>{l}</div>
        ))}
      </div>

      {/* Time wheels */}
      <div style={{margin:'10px 16px 4px', padding:'8px 12px', background:SF.card, borderRadius:16, border:'1px solid rgba(255,255,255,0.03)', display:'flex', alignItems:'center', gap:6}}>
        <Wheel values={hours} selectedIndex={23}/>
        <div style={{fontSize:22, fontWeight:700, color:SF.accent, paddingBottom:0}}>:</div>
        <Wheel values={mins} selectedIndex={11}/>
      </div>

      <div style={{padding:'12px 16px 0', display:'flex', gap:10}}>
        <a href="Nueva%20Tarea.html" style={{flex:1, padding:'14px 0', borderRadius:14, background:'rgba(255,255,255,0.04)', color:SF.text, display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:600, textDecoration:'none'}}>
          Cancelar
        </a>
        <a href="Nueva%20Tarea.html" style={{flex:1.6, padding:'14px 0', borderRadius:14, background:SF.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', gap:8, fontSize:14, fontWeight:700, boxShadow:'0 10px 24px rgba(45,127,249,0.40)', textDecoration:'none'}}>
          Establecer fecha
        </a>
      </div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:SF.bg, color:SF.text, height:'100%', position:'relative', overflow:'hidden', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <BgScreen/>
      <Scrim/>
      <Sheet/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
