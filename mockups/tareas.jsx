// Matix — Tareas screen (Android)

const C = {
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

// ── Icons (24px stroke) ────────────────────────────────────────
const ico = {
  search: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>
    </svg>
  ),
  plus: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  mic: (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/>
      <path d="M12 18v3"/>
    </svg>
  ),
  check: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12.5 10 17 19 7.5"/>
    </svg>
  ),
  home: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 11.5 12 4l9 7.5"/>
      <path d="M5 10.5V20h14v-9.5"/>
    </svg>
  ),
  tasks: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="4.5" width="17" height="15" rx="3"/>
      <path d="M7.5 9.5l2 2 4-4"/>
      <path d="M7.5 15.5h9"/>
    </svg>
  ),
  cal: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="5" width="17" height="15" rx="2.5"/>
      <path d="M3.5 10h17"/>
      <path d="M8 3v4M16 3v4"/>
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
  flame: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2c.5 4 4 5.5 4 9.5 0 2.2-1.8 4-4 4s-4-1.8-4-4c0-2.2 1.5-3 1.5-5.5 0 1.5 1.5 2 2.5 2-1-1-1-3.5 0-6z"/>
    </svg>
  ),
  clock: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
    </svg>
  ),
};

// ── Top bar ────────────────────────────────────────────────────
function TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 20px 10px',
    }}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{fontSize:12, color:C.muted, letterSpacing:0.4, fontWeight:500}}>
          Viernes · 23 may
        </span>
        <span style={{fontSize:26, color:C.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>
          Tareas
        </span>
      </div>
      <div style={{display:'flex', gap:10}}>
        <IconBtn href="Busqueda.html">{ico.search}</IconBtn>
        <IconBtn href="Filtros.html">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18M6 12h12M10 18h4"/></svg>
        </IconBtn>
        <IconBtn primary href="Nueva%20Tarea.html">{ico.plus}</IconBtn>
      </div>
    </div>
  );
}

function IconBtn({children, primary, href}) {
  return (
    <a href={href || '#'} style={{
      width:40, height:40, borderRadius:12,
      background: primary ? C.accent : C.card,
      color: primary ? '#fff' : C.text,
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow: primary ? '0 6px 16px rgba(45,127,249,0.35)' : 'none',
      textDecoration:'none',
    }}>{children}</a>
  );
}

// ── Pills ──────────────────────────────────────────────────────
function Pills() {
  const tabs = [
    {label:'Hoy', count:4, active:true},
    {label:'Esta semana', count:11},
    {label:'Todas', count:23},
    {label:'Completadas', count:48},
  ];
  return (
    <div style={{
      display:'flex', gap:8, padding:'8px 20px 14px',
      overflowX:'auto',
    }}>
      {tabs.map(t => (
        <div key={t.label} style={{
          flexShrink:0,
          display:'flex', alignItems:'center', gap:8,
          padding:'9px 16px',
          borderRadius:999,
          background: t.active ? C.accent : C.card,
          color: t.active ? '#fff' : C.muted,
          fontSize:14, fontWeight: t.active ? 600 : 500,
          boxShadow: t.active ? '0 4px 14px rgba(45,127,249,0.35)' : 'none',
        }}>
          {t.label}
          <span style={{
            fontSize:11, fontWeight:600,
            background: t.active ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.05)',
            color: t.active ? '#fff' : C.muted,
            padding:'2px 7px', borderRadius:999, lineHeight:1,
          }}>{t.count}</span>
        </div>
      ))}
    </div>
  );
}

// ── Group header ───────────────────────────────────────────────
function GroupHeader({label, color, count, accent}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:10,
      padding:'14px 20px 8px',
    }}>
      <span style={{
        width:6, height:6, borderRadius:'50%', background: color,
        boxShadow: accent ? `0 0 8px ${color}` : 'none',
      }}/>
      <span style={{
        fontSize:12, fontWeight:600, letterSpacing:0.8,
        color: accent ? color : C.muted, textTransform:'uppercase',
      }}>{label}</span>
      <span style={{
        fontSize:12, fontWeight:500, color: C.muted, opacity:0.6,
      }}>{count}</span>
      <div style={{flex:1, height:1, background:C.hairline, marginLeft:4}}/>
    </div>
  );
}

// ── Task card ──────────────────────────────────────────────────
function Task({title, meta, proyecto, priority, done, overdue, time, urgent}) {
  const prColor = priority === 'high' ? C.red : priority === 'med' ? C.amber : C.accent;
  return (
    <a href="Detalle%20Tarea.html" style={{
      margin:'6px 16px',
      padding:'14px 14px',
      background: overdue ? 'rgba(255,77,94,0.09)' : C.card,
      border: overdue ? '1px solid rgba(255,77,94,0.28)' : '1px solid rgba(255,255,255,0.03)',
      borderRadius:16,
      display:'flex', alignItems:'flex-start', gap:12,
      textDecoration:'none', color:'inherit',
    }}>
      {/* checkbox */}
      <div style={{
        width:22, height:22, borderRadius:'50%',
        background: done ? C.green : 'transparent',
        border: done ? 'none' : `1.8px solid ${overdue ? 'rgba(255,77,94,0.55)' : 'rgba(255,255,255,0.18)'}`,
        display:'flex', alignItems:'center', justifyContent:'center',
        flexShrink:0, marginTop:1,
      }}>
        {done && ico.check}
      </div>

      {/* body */}
      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'center', gap:8}}>
          <span style={{
            width:7, height:7, borderRadius:'50%', background: prColor, flexShrink:0,
          }}/>
          <span style={{
            fontSize:15, fontWeight:600, color: done ? C.muted : C.text,
            textDecoration: done ? 'line-through' : 'none',
            letterSpacing:-0.1, lineHeight:1.25,
          }}>{title}</span>
        </div>
        <div style={{
          display:'flex', alignItems:'center', gap:8, marginTop:6,
          fontSize:12, color: C.muted,
        }}>
          <span style={{
            display:'inline-flex', alignItems:'center', gap:4,
            padding:'2px 7px', borderRadius:6,
            background:'rgba(255,255,255,0.04)',
            color: C.muted, fontWeight:500,
          }}>{meta}</span>
          {proyecto && (
            <span style={{
              display:'inline-flex', alignItems:'center', gap:4,
              padding:'2px 7px', borderRadius:6,
              background:'rgba(45,127,249,0.10)',
              color: C.accent, fontWeight:600,
              fontSize:11.5,
            }}>
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 22V4"/><path d="M5 4h12l-2.5 4.5L17 13H5"/>
              </svg>
              <span>{proyecto}</span>
            </span>
          )}
          <span style={{display:'inline-flex', alignItems:'center', gap:4, color: overdue ? C.red : C.muted}}>
            {ico.clock}
            <span style={{fontWeight: overdue ? 600 : 500}}>{time}</span>
          </span>
          {urgent && (
            <span style={{display:'inline-flex', alignItems:'center', gap:3, color:C.red, fontWeight:600}}>
              {ico.flame}<span>urgente</span>
            </span>
          )}
        </div>
      </div>
    </a>
  );
}

// ── Bottom nav ─────────────────────────────────────────────────
function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ico.home},
    {key:'tasks', label:'Tareas', icon:ico.tasks, active:true},
    {key:'cal', label:'Calendario', icon:ico.cal},
    {key:'uni', label:'Universidad', icon:ico.uni},
    {key:'notes', label:'Apuntes', icon:ico.notes},
  ];
  return (
    <div style={{
      background: C.bg,
      borderTop: `1px solid ${C.hairline}`,
      padding:'10px 8px 8px',
      display:'flex', justifyContent:'space-around',
    }}>
      {items.map(it => (
        <div key={it.key} style={{
          display:'flex', flexDirection:'column', alignItems:'center', gap:4,
          flex:1, padding:'4px 0',
          color: it.active ? C.accent : C.muted,
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

// ── Floating mic ───────────────────────────────────────────────
function FAB() {
  return (
    <div style={{
      position:'absolute', right:18, bottom:96,
      width:60, height:60, borderRadius:'50%',
      background: C.accent, color:'#fff',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)',
    }}>
      {ico.mic}
    </div>
  );
}

// ── Screen ─────────────────────────────────────────────────────
function TareasScreen() {
  return (
    <div style={{
      background: C.bg, color: C.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <TopBar/>
      <Pills/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <GroupHeader label="Vencidas" color={C.red} count="1" accent/>
        <Task
          title="Entregar informe de Estadística II"
          meta="Estadística II"
          time="Ayer · 23:59"
          priority="high"
          overdue
          urgent
        />

        <GroupHeader label="Hoy" color={C.text} count="3"/>
        <Task
          title="Validar pantalla de Tareas en el teléfono"
          meta="Matix #1"
          proyecto="Matix"
          time="11:00"
          priority="med"
        />
        <Task
          title="Subir fotos del último drop"
          meta="OnExotic #2"
          proyecto="OnExotic"
          time="18:30"
          priority="high"
        />
        <Task
          title="Revisar notas de la clase del martes"
          meta="Filosofía de la Ciencia"
          time="21:00"
          priority="low"
          done
        />

        <GroupHeader label="Mañana" color={C.text} count="2"/>
        <Task
          title="Preparar exposición grupal"
          meta="Marketing Digital"
          time="09:30"
          priority="med"
        />
        <Task
          title="Devolver libros a la biblioteca"
          meta="Personal"
          time="12:00"
          priority="low"
        />
      </div>

      <MatixFAB/>
      <MatixBottomNav active="tasks"/>
    </div>
  );
}

// ── Mount ──────────────────────────────────────────────────────
function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <TareasScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
