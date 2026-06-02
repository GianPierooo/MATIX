// Matix — Menú de adjuntar (spec del chat)
// Estado colapsado de la barra + menú tipo WhatsApp al tocar "+"

const M = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

// ── Icons ─────────────────────────────────────────────────────
const I = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  spark: <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  sparkBig: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  plus: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>,
  mic: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  send: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12 19 5l-3.5 14L11 13z"/></svg>,
  // Attach option icons (stroke, tinted per-option)
  doc: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-11A.5.5 0 0 1 6 20V4a.5.5 0 0 1 .5-.5z"/><path d="M14 3.5v4h4"/><path d="M9 13h6M9 16.5h4"/></svg>,
  photo: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="8.5" cy="10" r="1.6"/><path d="M4 17l4.5-4.5 3.5 3.5 3-3 5 5"/></svg>,
  camera: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 8.5h3l1.5-2h7L17 8.5h3a1 1 0 0 1 1 1V18a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9.5a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.2"/></svg>,
  audio: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v0M8 8v8M12 5v14M16 9v6M20 12v0"/></svg>,
  contact: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="9" r="3.4"/><path d="M5.5 19a6.5 6.5 0 0 1 13 0z"/></svg>,
};

// ── Chat backdrop (a couple of bubbles so the bar has context) ──
function ChatBackdrop({dim}) {
  return (
    <div style={{flex:1, overflow:'hidden', padding:'10px 16px 8px', display:'flex', flexDirection:'column', gap:12, opacity: dim?0.5:1, transition:'opacity 0.2s'}}>
      {/* Matix bubble */}
      <div style={{display:'flex', gap:10, alignItems:'flex-start'}}>
        <div style={{width:28, height:28, borderRadius:'50%', background:hexA(M.accent,0.16), border:`1.2px solid ${M.accent}`, color:M.accent, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, marginTop:2}}>{I.spark}</div>
        <div style={{maxWidth:'78%', padding:'11px 14px', background:M.card, borderRadius:'4px 16px 16px 16px', fontSize:14, lineHeight:1.5, border:'1px solid rgba(255,255,255,0.03)'}}>
          ¿Quieres adjuntar el sílabo del curso o una foto de tus apuntes? Puedo leerlos y crear tareas.
        </div>
      </div>
      {/* user bubble */}
      <div style={{display:'flex', justifyContent:'flex-end'}}>
        <div style={{maxWidth:'78%', padding:'10px 14px', background:M.accent, color:'#fff', borderRadius:'16px 16px 4px 16px', fontSize:14, lineHeight:1.45, fontWeight:500, boxShadow:'0 4px 14px rgba(45,127,249,0.25)'}}>
          Sí, te paso el PDF del sílabo
        </div>
      </div>
    </div>
  );
}

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px', borderBottom:`1px solid ${M.hairline}`}}>
      <a href="Inicio.html" style={{width:40, height:40, borderRadius:12, background:M.card, color:M.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{I.close}</a>
      <div style={{display:'flex', alignItems:'center', gap:10}}>
        <div style={{width:32, height:32, borderRadius:'50%', background:hexA(M.accent,0.16), border:`1.5px solid ${M.accent}`, color:M.accent, display:'flex', alignItems:'center', justifyContent:'center', boxShadow:`0 0 0 3px ${hexA(M.accent,0.10)}`}}>{I.sparkBig}</div>
        <div style={{display:'flex', flexDirection:'column'}}>
          <span style={{fontSize:14.5, fontWeight:700, color:M.text, letterSpacing:-0.2}}>Matix</span>
          <span style={{fontSize:11, color:M.green, fontWeight:600, display:'inline-flex', alignItems:'center', gap:5}}>
            <span style={{width:6, height:6, borderRadius:'50%', background:M.green, boxShadow:`0 0 8px ${M.green}`}}/>
            Activo
          </span>
        </div>
      </div>
      <div style={{width:40, height:40, borderRadius:12, background:M.card, color:M.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{I.more}</div>
    </div>
  );
}

// ── Input bar (collapsed / open variants share this) ──────────
function InputBar({open, onToggle}) {
  return (
    <div style={{padding:'8px 12px 14px', borderTop:`1px solid ${M.hairline}`, background:M.bg, display:'flex', alignItems:'center', gap:8, position:'relative', zIndex:2}}>
      {/* mic — left */}
      <div style={{width:42, height:42, borderRadius:13, background:M.card, color:M.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, border:'1px solid rgba(255,255,255,0.04)'}}>{I.mic}</div>

      {/* attach "+" — rotates to x when open */}
      <button onClick={onToggle} style={{
        width:42, height:42, borderRadius:13, flexShrink:0,
        background: open ? M.accent : M.card,
        color: open ? '#fff' : M.muted,
        border: open ? 'none' : '1px solid rgba(255,255,255,0.04)',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow: open ? `0 6px 16px ${hexA(M.accent,0.35)}` : 'none',
        transition:'all 0.2s', cursor:'pointer', padding:0,
      }}>
        <span style={{display:'flex', transform: open?'rotate(45deg)':'rotate(0deg)', transition:'transform 0.2s'}}>{I.plus}</span>
      </button>

      {/* text field */}
      <div style={{flex:1, minHeight:44, padding:'12px 16px', background:M.card, borderRadius:14, color:M.muted, fontSize:14, fontWeight:500, display:'flex', alignItems:'center', border:'1px solid rgba(255,255,255,0.04)'}}>
        Escribe a Matix o toca el mic
      </div>

      {/* send */}
      <div style={{width:44, height:44, borderRadius:14, background:M.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, boxShadow:'0 6px 16px rgba(45,127,249,0.35)'}}>{I.send}</div>
    </div>
  );
}

// ── Attach menu (WhatsApp-style grid sheet) ────────────────────
const OPTIONS = [
  {key:'doc',     label:'Documento',  icon:I.doc,     color:M.purple},
  {key:'photo',   label:'Foto/Video', icon:I.photo,   color:M.accent},
  {key:'camera',  label:'Cámara',     icon:I.camera,  color:M.red},
  {key:'audio',   label:'Audio',      icon:I.audio,   color:M.amber},
  {key:'contact', label:'Contacto',   icon:I.contact, color:M.green},
];

function AttachOption({opt, idx}) {
  return (
    <div style={{
      display:'flex', flexDirection:'column', alignItems:'center', gap:9,
    }}>
      <div style={{
        width:62, height:62, borderRadius:20,
        background: hexA(opt.color, 0.16),
        border: `1px solid ${hexA(opt.color, 0.32)}`,
        color: opt.color,
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow: `0 8px 22px ${hexA(opt.color, 0.22)}`,
      }}>{opt.icon}</div>
      <span style={{fontSize:12, fontWeight:600, color:M.text, letterSpacing:0.1}}>{opt.label}</span>
    </div>
  );
}

function AttachMenu() {
  return (
    <div style={{
      position:'relative', zIndex:2,
      background:M.cardHi,
      borderTopLeftRadius:24, borderTopRightRadius:24,
      borderTop:`1px solid ${M.hairline}`,
      boxShadow:'0 -20px 50px rgba(0,0,0,0.45)',
      padding:'10px 16px 20px',
    }}>
        {/* grab handle */}
        <div style={{display:'flex', justifyContent:'center', padding:'2px 0 12px'}}>
          <div style={{width:42, height:5, borderRadius:99, background:'rgba(255,255,255,0.18)'}}/>
        </div>

        <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 4px 14px'}}>
          <span style={{fontSize:15, fontWeight:700, color:M.text, letterSpacing:-0.2}}>Adjuntar</span>
          <span style={{fontSize:12, color:M.muted, fontWeight:500}}>Compártelo con Matix</span>
        </div>

        {/* grid — 4 columns; wraps, leaving room for future options */}
        <div style={{
          display:'grid',
          gridTemplateColumns:'repeat(4, 1fr)',
          rowGap:20, columnGap:8,
          padding:'4px 0 0',
        }}>
          {OPTIONS.map((o,i) => <AttachOption key={o.key} opt={o} idx={i}/>)}
        </div>
      </div>
  );
}

// ── Screen ────────────────────────────────────────────────────
function Screen() {
  const [open, setOpen] = React.useState(true);
  return (
    <div style={{background:M.bg, color:M.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif", overflow:'hidden'}}>
      <style>{`
        @keyframes pop { from { opacity:0; transform: translateY(10px) scale(0.85); } to { opacity:1; transform:none; } }
        @keyframes sheetUp { from { transform: translateY(100%); } to { transform:none; } }
      `}</style>

      <TopBar/>
      <ChatBackdrop dim={open}/>

      {/* scrim over chat region when menu open */}
      {open && (
        <div onClick={() => setOpen(false)} style={{position:'absolute', inset:0, background:'rgba(0,0,0,0.35)', backdropFilter:'blur(1px)', zIndex:1}}/>
      )}

      {open && <AttachMenu/>}

      <InputBar open={open} onToggle={() => setOpen(o => !o)}/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
