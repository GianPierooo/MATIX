// Matix — Escuchando (voz activa)

const ME = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const me = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  keyboard: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h10"/></svg>,
  mic: <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  stop: <svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>,
  spark: <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
};

// Vertical waveform bars
function Wave() {
  const bars = Array.from({length:38}, (_,i) => {
    // pseudo-random but deterministic
    const n = Math.sin(i*1.7)*Math.cos(i*0.6+1) + Math.sin(i*0.3);
    const h = 18 + Math.abs(n) * 50 + (i%5===0 ? 12 : 0);
    return Math.min(86, Math.max(8, h));
  });
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'center', gap:5, height:100, padding:'0 20px'}}>
      {bars.map((h,i) => (
        <div key={i} style={{
          width:4,
          height: h,
          borderRadius:99,
          background: i < 22 ? ME.accent : hexA(ME.accent, 0.35),
          boxShadow: i < 22 ? `0 0 8px ${hexA(ME.accent,0.5)}` : 'none',
        }}/>
      ))}
    </div>
  );
}

// Orbital glow rings around mic
function Orb() {
  return (
    <div style={{position:'relative', width:200, height:200, display:'flex', alignItems:'center', justifyContent:'center'}}>
      {/* outer rings */}
      <div style={{position:'absolute', inset:0, borderRadius:'50%', border:`1px solid ${hexA(ME.accent,0.16)}`, boxShadow:`0 0 60px ${hexA(ME.accent,0.10)}`}}/>
      <div style={{position:'absolute', inset:18, borderRadius:'50%', border:`1px solid ${hexA(ME.accent,0.25)}`}}/>
      <div style={{position:'absolute', inset:38, borderRadius:'50%', border:`1.5px solid ${hexA(ME.accent,0.40)}`}}/>
      {/* core orb */}
      <div style={{
        position:'relative',
        width:104, height:104, borderRadius:'50%',
        background:`radial-gradient(circle at 30% 30%, ${hexA(ME.accent,0.95)} 0%, ${ME.accent} 50%, ${hexA(ME.accent,0.65)} 100%)`,
        boxShadow:`0 20px 60px ${hexA(ME.accent,0.55)}, 0 0 0 6px ${hexA(ME.accent,0.14)}, inset 0 -8px 20px rgba(0,0,0,0.25)`,
        display:'flex', alignItems:'center', justifyContent:'center',
        color:'#fff',
      }}>
        {me.mic}
      </div>
    </div>
  );
}

function Chip({children}) {
  return (
    <div style={{
      padding:'9px 14px', borderRadius:99,
      background:ME.card, color:ME.muted,
      fontSize:13, fontWeight:500,
      border:'1px solid rgba(255,255,255,0.04)',
      whiteSpace:'nowrap',
    }}>{children}</div>
  );
}

function Screen() {
  return (
    <div style={{
      background:ME.bg, color:ME.text, height:'100%',
      display:'flex', flexDirection:'column', position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
      overflow:'hidden',
    }}>
      {/* ambient glow */}
      <div style={{
        position:'absolute', top:'30%', left:'50%', transform:'translate(-50%,-50%)',
        width:520, height:520, borderRadius:'50%',
        background:`radial-gradient(circle, ${hexA(ME.accent,0.22)} 0%, transparent 60%)`,
        pointerEvents:'none', zIndex:0,
      }}/>

      <div style={{position:'relative', zIndex:1, display:'flex', flexDirection:'column', height:'100%'}}>

        {/* Top bar */}
        <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
          <a href="Matix%20Chat.html" style={{width:40, height:40, borderRadius:12, background:'rgba(255,255,255,0.04)', color:ME.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{me.close}</a>
          <div style={{display:'inline-flex', alignItems:'center', gap:6, padding:'5px 12px 5px 10px', borderRadius:99, background:hexA(ME.accent,0.16), border:`1px solid ${hexA(ME.accent,0.35)}`, color:ME.accent, fontSize:11.5, fontWeight:700, letterSpacing:0.6, textTransform:'uppercase'}}>
            <span style={{width:7, height:7, borderRadius:'50%', background:ME.accent, boxShadow:`0 0 10px ${ME.accent}`, animation:'pulse 1.4s infinite'}}/>
            <span>Matix · Escuchando</span>
          </div>
          <div style={{width:40, height:40}}/>
        </div>

        <style>{`
          @keyframes pulse { 0%,100% { opacity:1; transform:scale(1);} 50% { opacity:.5; transform:scale(0.85);} }
        `}</style>

        {/* Orb area */}
        <div style={{flex:'1 1 auto', display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'flex-start', paddingTop:36}}>
          <Orb/>

          <div style={{marginTop:16, fontSize:11, fontWeight:600, color:ME.muted, letterSpacing:1.6, textTransform:'uppercase'}}>
            Estás hablando…
          </div>

          <Wave/>

          {/* Live transcription */}
          <div style={{marginTop:6, padding:'0 28px', textAlign:'center', maxWidth:340}}>
            <div style={{fontSize:20, fontWeight:600, color:ME.text, letterSpacing:-0.3, lineHeight:1.35, textWrap:'pretty'}}>
              «Recuérdame entregar el informe de Física esta noche
              <span style={{color:ME.muted, fontWeight:500}}> a las once…</span>
              <span style={{display:'inline-block', width:2, height:22, background:ME.accent, marginLeft:3, verticalAlign:'-4px', animation:'blink 1s steps(1) infinite'}}/>
            </div>
            <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>
          </div>
        </div>

        {/* Hint chips */}
        <div style={{padding:'4px 16px 16px'}}>
          <div style={{fontSize:11, fontWeight:600, color:ME.muted, letterSpacing:0.8, textTransform:'uppercase', textAlign:'center', marginBottom:10}}>
            También puedes decir
          </div>
          <div style={{display:'flex', gap:8, overflowX:'auto', justifyContent:'center', flexWrap:'wrap'}}>
            <Chip>“Crea una tarea para mañana”</Chip>
            <Chip>“¿Qué tengo el viernes?”</Chip>
            <Chip>“Resume mi última clase”</Chip>
          </div>
        </div>

        {/* Bottom controls */}
        <div style={{padding:'14px 16px 22px', display:'flex', alignItems:'center', justifyContent:'center', gap:32}}>
          <div style={{width:52, height:52, borderRadius:'50%', background:ME.card, color:ME.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{me.keyboard}</div>
          <div style={{
            width:74, height:74, borderRadius:'50%',
            background:ME.red, color:'#fff',
            display:'flex', alignItems:'center', justifyContent:'center',
            boxShadow:`0 14px 30px ${hexA(ME.red,0.45)}, 0 0 0 6px ${hexA(ME.red,0.12)}`,
          }}>{me.stop}</div>
          <div style={{
            display:'flex', flexDirection:'column', alignItems:'center', gap:2,
          }}>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'5px 10px', borderRadius:99, background:'rgba(255,255,255,0.04)', color:ME.muted, fontSize:10.5, fontWeight:700, letterSpacing:0.5}}>
              {me.spark}<span>0:14</span>
            </div>
            <span style={{fontSize:10, color:ME.muted, fontWeight:500, marginTop:6}}>Toca para detener</span>
          </div>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
