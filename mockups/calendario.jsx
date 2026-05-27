// Matix — Calendario screen (Android)

const CC = {
  bg: '#0B0F1A',
  card: '#161B2E',
  cardHi: '#1B2138',
  accent: '#2D7FF9',
  green: '#21D07A',
  red: '#FF4D5E',
  amber: '#E0A33A',
  text: '#E8ECF4',
  muted: '#8A93A8',
  hairline: 'rgba(255,255,255,0.06)',
};

function hexA(hex, a) {
  const h = hex.replace('#','');
  const r = parseInt(h.slice(0,2),16), g = parseInt(h.slice(2,4),16), b = parseInt(h.slice(4,6),16);
  return `rgba(${r},${g},${b},${a})`;
}

// ── Icons ──────────────────────────────────────────────────────
const ci = {
  plus: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  chevL: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M15 6l-6 6 6 6"/>
    </svg>
  ),
  chevR: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 6l6 6-6 6"/>
    </svg>
  ),
  mic: (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/>
      <path d="M12 18v3"/>
    </svg>
  ),
  pin: (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/>
      <circle cx="12" cy="9" r="2.4"/>
    </svg>
  ),
  home: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/>
    </svg>
  ),
  tasks: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="4.5" width="17" height="15" rx="3"/>
      <path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/>
    </svg>
  ),
  cal: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="5" width="17" height="15" rx="2.5"/>
      <path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/>
    </svg>
  ),
  uni: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/>
      <path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/>
    </svg>
  ),
  notes: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/>
      <path d="M14.5 3.5v4h4"/>
      <path d="M8 12h7M8 15.5h5"/>
    </svg>
  ),
};

// ── Top bar ────────────────────────────────────────────────────
function TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 14px 10px', gap:10,
    }}>
      <a href="Inicio.html" style={{
        width:40, height:40, borderRadius:12,
        background:CC.card, color:CC.text,
        display:'flex', alignItems:'center', justifyContent:'center',
        textDecoration:'none', flexShrink:0,
      }}>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
      </a>
      <div style={{display:'flex', flexDirection:'column', flex:1, minWidth:0}}>
        <span style={{fontSize:12, color:CC.muted, letterSpacing:0.4, fontWeight:500}}>
          Sábado · 23 may
        </span>
        <span style={{fontSize:22, color:CC.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>
          Calendario
        </span>
      </div>
      <a href="Nuevo%20Evento.html" style={{
        width:40, height:40, borderRadius:12,
        background:CC.accent, color:'#fff',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 6px 16px rgba(45,127,249,0.35)',
        textDecoration:'none', flexShrink:0,
      }}>{ci.plus}</a>
    </div>
  );
}

// ── Segmented control ──────────────────────────────────────────
function Segmented() {
  const opts = [
    {k:'m', l:'Mes', active:true},
    {k:'w', l:'Semana', href:'Calendario%20Semana.html'},
    {k:'d', l:'Día', href:'Calendario%20Dia.html'},
  ];
  return (
    <div style={{
      margin:'6px 20px 14px',
      background: CC.card, padding:4, borderRadius:12,
      display:'flex', gap:4,
    }}>
      {opts.map(o => (
        <a key={o.k} href={o.href || '#'} style={{
          flex:1, padding:'9px 0', textAlign:'center',
          borderRadius:9,
          background: o.active ? CC.accent : 'transparent',
          color: o.active ? '#fff' : CC.muted,
          fontSize:13, fontWeight:600,
          boxShadow: o.active ? '0 4px 14px rgba(45,127,249,0.35)' : 'none',
          textDecoration:'none',
        }}>{o.l}</a>
      ))}
    </div>
  );
}

// ── Month nav ──────────────────────────────────────────────────
function MonthNav() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'2px 22px 10px',
    }}>
      <div style={{display:'flex', alignItems:'center', gap:8}}>
        <span style={{fontSize:18, fontWeight:700, color:CC.text, letterSpacing:-0.3}}>Mayo</span>
        <span style={{fontSize:18, fontWeight:500, color:CC.muted, letterSpacing:-0.3}}>2026</span>
      </div>
      <div style={{display:'flex', gap:6}}>
        <div style={{
          width:30, height:30, borderRadius:9,
          background:'rgba(255,255,255,0.04)', color:CC.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>{ci.chevL}</div>
        <div style={{
          width:30, height:30, borderRadius:9,
          background:'rgba(255,255,255,0.04)', color:CC.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>{ci.chevR}</div>
      </div>
    </div>
  );
}

// ── Month grid ─────────────────────────────────────────────────
// May 2026: May 1 is Friday. Today = 23 (Saturday).
const WEEKDAYS = ['L','M','X','J','V','S','D'];

// Days with events: { day: [colors...] }
const EVENT_DOTS = {
  4:  [CC.accent],
  6:  [CC.accent, CC.amber],
  8:  [CC.green],
  11: [CC.accent],
  13: [CC.red],
  15: [CC.accent, CC.green],
  19: [CC.accent],
  22: [CC.red, CC.amber],
  23: [CC.accent, CC.green, CC.red],   // today
  25: [CC.accent],
  27: [CC.amber],
  29: [CC.red],
};

const TODAY = 23;

function MonthGrid() {
  // Build cells: prev-month grayed, current month, next-month grayed.
  // May 1 = Friday → index 4 (Mon=0). So 4 prev-cells from April (April has 30 days), and after 31, fill rest.
  const cells = [];
  for (let i = 0; i < 4; i++) cells.push({d: 27+i, muted:true});  // April 27..30
  for (let d = 1; d <= 31; d++) cells.push({d});
  let nx = 1;
  while (cells.length % 7 !== 0) { cells.push({d: nx++, muted:true}); }
  // ensure 6 rows
  while (cells.length < 42) { cells.push({d: nx++, muted:true}); }

  return (
    <div style={{padding:'0 16px 6px'}}>
      {/* weekday header */}
      <div style={{
        display:'grid', gridTemplateColumns:'repeat(7,1fr)',
        padding:'0 4px 8px',
      }}>
        {WEEKDAYS.map((w,i) => (
          <div key={i} style={{
            textAlign:'center', fontSize:11, fontWeight:600,
            color: i >= 5 ? hexA(CC.muted, 0.7) : CC.muted,
            letterSpacing:0.6,
          }}>{w}</div>
        ))}
      </div>

      {/* grid */}
      <div style={{
        display:'grid', gridTemplateColumns:'repeat(7,1fr)',
        gap:2,
      }}>
        {cells.map((c, idx) => {
          const isToday = !c.muted && c.d === TODAY;
          const dots = !c.muted ? (EVENT_DOTS[c.d] || []) : [];
          return (
            <div key={idx} style={{
              aspectRatio:'1 / 1',
              display:'flex', flexDirection:'column',
              alignItems:'center', justifyContent:'center',
              position:'relative',
              gap:3,
            }}>
              <div style={{
                width:32, height:32, borderRadius:'50%',
                display:'flex', alignItems:'center', justifyContent:'center',
                background: isToday ? CC.accent : 'transparent',
                color: isToday ? '#fff'
                  : c.muted ? hexA(CC.muted, 0.45)
                  : CC.text,
                fontSize:14, fontWeight: isToday ? 700 : 500,
                boxShadow: isToday ? '0 6px 14px rgba(45,127,249,0.45)' : 'none',
              }}>{c.d}</div>
              <div style={{display:'flex', gap:3, height:4}}>
                {dots.slice(0,3).map((col, i) => (
                  <span key={i} style={{
                    width:4, height:4, borderRadius:'50%',
                    background: isToday ? '#fff' : col,
                    opacity: isToday ? 0.85 : 1,
                  }}/>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Events list ────────────────────────────────────────────────
function EventRow({time, endTime, title, sub, color, location}) {
  return (
    <a href="Detalle%20Evento.html" style={{
      display:'flex', alignItems:'stretch', gap:14,
      padding:'12px 18px',
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{
        width:48, flexShrink:0, paddingTop:2,
        display:'flex', flexDirection:'column', alignItems:'flex-end',
      }}>
        <span style={{fontSize:13, fontWeight:600, color:CC.text, letterSpacing:0.2}}>{time}</span>
        {endTime && <span style={{fontSize:11, color:CC.muted, marginTop:2}}>{endTime}</span>}
      </div>
      <div style={{
        width:4, borderRadius:4, background:color, flexShrink:0,
        boxShadow:`0 0 12px ${hexA(color, 0.45)}`,
      }}/>
      <div style={{
        flex:1, minWidth:0,
        background: CC.card,
        borderRadius:14,
        padding:'12px 14px',
      }}>
        <div style={{fontSize:14.5, fontWeight:600, color:CC.text, letterSpacing:-0.1}}>{title}</div>
        <div style={{
          display:'flex', alignItems:'center', gap:6,
          marginTop:5, fontSize:12, color:CC.muted, fontWeight:500,
        }}>
          <span>{sub}</span>
          {location && (
            <>
              <span style={{width:3, height:3, borderRadius:'50%', background:CC.muted, opacity:0.6}}/>
              <span style={{display:'inline-flex', alignItems:'center', gap:3}}>
                {ci.pin}{location}
              </span>
            </>
          )}
        </div>
      </div>
    </a>
  );
}

function EventsList() {
  return (
    <>
      <div style={{
        display:'flex', alignItems:'baseline', justifyContent:'space-between',
        padding:'18px 22px 6px',
      }}>
        <div style={{display:'flex', alignItems:'baseline', gap:8}}>
          <span style={{fontSize:15, fontWeight:700, color:CC.text, letterSpacing:-0.2}}>
            Eventos de hoy
          </span>
          <span style={{fontSize:12, color:CC.muted, fontWeight:600}}>3</span>
        </div>
        <a href="Calendario%20Semana.html" style={{fontSize:12, color:CC.accent, fontWeight:600, textDecoration:'none'}}>Ver semana</a>
      </div>

      <EventRow
        time="09:00" endTime="10:30"
        color={CC.accent}
        title="Cálculo Vectorial — Clase"
        sub="Prof. Mendoza" location="Aula 4B"
      />
      <EventRow
        time="14:00" endTime="15:00"
        color={CC.green}
        title="Gimnasio"
        sub="Personal"
      />
      <EventRow
        time="23:59"
        color={CC.red}
        title="Entrega — Informe Estadística II"
        sub="Estadística II"
      />
    </>
  );
}

// ── FAB ────────────────────────────────────────────────────────
function FAB() {
  return (
    <div style={{
      position:'absolute', right:18, bottom:96,
      width:60, height:60, borderRadius:'50%',
      background: CC.accent, color:'#fff',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)',
    }}>{ci.mic}</div>
  );
}

// ── Bottom nav ─────────────────────────────────────────────────
function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ci.home},
    {key:'tasks', label:'Tareas', icon:ci.tasks},
    {key:'cal', label:'Calendario', icon:ci.cal, active:true},
    {key:'uni', label:'Universidad', icon:ci.uni},
    {key:'notes', label:'Apuntes', icon:ci.notes},
  ];
  return (
    <div style={{
      background: CC.bg,
      borderTop: `1px solid ${CC.hairline}`,
      padding:'10px 8px 8px',
      display:'flex', justifyContent:'space-around',
    }}>
      {items.map(it => (
        <div key={it.key} style={{
          display:'flex', flexDirection:'column', alignItems:'center', gap:4,
          flex:1, padding:'4px 0',
          color: it.active ? CC.accent : CC.muted,
        }}>
          {it.active ? (
            <div style={{
              padding:'4px 14px', borderRadius:999,
              background:'rgba(45,127,249,0.16)',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>{it.icon}</div>
          ) : it.icon}
          <span style={{
            fontSize:10.5, fontWeight: it.active ? 600 : 500,
            letterSpacing:0.1,
          }}>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

// ── Screen ─────────────────────────────────────────────────────
function CalendarioScreen() {
  return (
    <div style={{
      background: CC.bg, color: CC.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <TopBar/>
      <Segmented/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <MonthNav/>
        <MonthGrid/>

        <div style={{height:1, background:CC.hairline, margin:'14px 22px 0'}}/>

        <EventsList/>
      </div>

      <MatixFAB/>
      <MatixBottomNav active="home"/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <CalendarioScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
