// Matix — Universidad (cursos)

const UC = {
  bg: '#0B0F1A',
  card: '#161B2E',
  cardHi: '#1B2138',
  accent: '#2D7FF9',
  green: '#21D07A',
  red: '#FF4D5E',
  amber: '#E0A33A',
  purple: '#9B7BFF',
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
const ui = {
  plus: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  mic: (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>
    </svg>
  ),
  clock: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
    </svg>
  ),
  doc: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M7 3.5h7l3.5 3.5V20a.5.5 0 0 1-.5.5h-10a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/>
      <path d="M14 3.5v3.5h3.5"/>
    </svg>
  ),
  exam: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="5.5" y="3.5" width="13" height="17" rx="1.5"/>
      <path d="M9 8h6M9 12h6M9 16h4"/>
    </svg>
  ),
  chev: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 6l6 6-6 6"/>
    </svg>
  ),
  trend: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 17l5-5 4 3 7-7"/><path d="M14 8h6v6"/>
    </svg>
  ),
  spark: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2l2 6 6 2-6 2-2 6-2-6-6-2 6-2z"/>
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
      padding:'14px 20px 10px',
    }}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{fontSize:12, color:UC.muted, letterSpacing:0.4, fontWeight:500}}>
          Ciclo 2026 · I
        </span>
        <span style={{fontSize:26, color:UC.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>
          Universidad
        </span>
      </div>
      <a href="Nuevo%20Curso.html" style={{
        width:40, height:40, borderRadius:12,
        background:UC.accent, color:'#fff',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 6px 16px rgba(45,127,249,0.35)',
        textDecoration:'none',
      }}>{ui.plus}</a>
    </div>
  );
}

// ── Mini sparkline ─────────────────────────────────────────────
function Sparkline({color}) {
  // simple ascending wave
  const points = [
    [0,18], [12,14], [24,16], [36,11], [48,13], [60,9], [72,11], [84,6], [96,8],
  ];
  const d = points.map((p,i) => (i===0?'M':'L')+p[0]+' '+p[1]).join(' ');
  const fill = `${d} L96 22 L0 22 Z`;
  return (
    <svg width="96" height="24" viewBox="0 0 96 24" style={{display:'block'}}>
      <defs>
        <linearGradient id="spk" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35"/>
          <stop offset="100%" stopColor={color} stopOpacity="0"/>
        </linearGradient>
      </defs>
      <path d={fill} fill="url(#spk)"/>
      <path d={d} fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

// ── Summary card ───────────────────────────────────────────────
function SummaryCard() {
  return (
    <div style={{
      margin:'2px 16px 8px',
      background: UC.card,
      borderRadius:18,
      padding:16,
      border:'1px solid rgba(255,255,255,0.04)',
    }}>
      <div style={{display:'flex', alignItems:'flex-start', gap:16}}>
        {/* avg */}
        <div style={{flex:1, minWidth:0}}>
          <div style={{
            fontSize:11, fontWeight:600, color:UC.muted,
            letterSpacing:0.7, textTransform:'uppercase',
          }}>Promedio general</div>
          <div style={{display:'flex', alignItems:'baseline', gap:6, marginTop:6}}>
            <span style={{
              fontSize:38, fontWeight:700, color:UC.text,
              letterSpacing:-1.4, lineHeight:1,
            }}>16.4</span>
            <span style={{fontSize:13, color:UC.muted, fontWeight:600}}>/20</span>
          </div>
          <div style={{
            display:'inline-flex', alignItems:'center', gap:4, marginTop:8,
            padding:'3px 8px', borderRadius:999,
            background: hexA(UC.green, 0.14),
            color: UC.green, fontSize:11, fontWeight:600,
          }}>
            {ui.trend}<span>+0.6 vs. ciclo previo</span>
          </div>
        </div>

        {/* divider */}
        <div style={{width:1, alignSelf:'stretch', background:UC.hairline, margin:'4px 0'}}/>

        {/* next exam */}
        <div style={{flex:1, minWidth:0}}>
          <div style={{
            fontSize:11, fontWeight:600, color:UC.muted,
            letterSpacing:0.7, textTransform:'uppercase',
          }}>Próximo examen</div>
          <div style={{
            marginTop:6, fontSize:15, fontWeight:700, color:UC.text,
            letterSpacing:-0.2, lineHeight:1.15,
          }}>Cálculo III</div>
          <div style={{
            display:'inline-flex', alignItems:'center', gap:5, marginTop:8,
            padding:'4px 9px', borderRadius:8,
            background: hexA(UC.amber, 0.14),
            border: `1px solid ${hexA(UC.amber, 0.35)}`,
            color: UC.amber, fontSize:12, fontWeight:600,
          }}>
            {ui.clock}<span>en 2 días</span>
          </div>
        </div>
      </div>

      {/* tiny trend bar across the whole card */}
      <div style={{marginTop:14, display:'flex', alignItems:'center', gap:10}}>
        <Sparkline color={UC.accent}/>
        <div style={{flex:1}}/>
        <span style={{fontSize:11, color:UC.muted, fontWeight:500}}>
          Últimos 6 ciclos
        </span>
      </div>
    </div>
  );
}

// ── Course card ────────────────────────────────────────────────
function CourseCard({color, initial, name, prof, schedule, deliveries, exam, grade}) {
  return (
    <a href="Detalle%20Curso.html" style={{
      margin:'8px 16px 0',
      background: UC.card,
      borderRadius:18,
      padding:'14px 14px',
      border:'1px solid rgba(255,255,255,0.03)',
      display:'flex', alignItems:'flex-start', gap:14,
      position:'relative', overflow:'hidden',
      textDecoration:'none', color:'inherit',
    }}>
      {/* subtle color side glow */}
      <div style={{
        position:'absolute', left:0, top:0, bottom:0, width:3,
        background: color,
        boxShadow:`0 0 16px ${hexA(color, 0.5)}`,
      }}/>

      {/* avatar circle */}
      <div style={{
        width:48, height:48, borderRadius:'50%',
        background: hexA(color, 0.16),
        border: `1.5px solid ${hexA(color, 0.55)}`,
        color: color,
        display:'flex', alignItems:'center', justifyContent:'center',
        fontSize:20, fontWeight:700, letterSpacing:-0.5,
        flexShrink:0,
      }}>{initial}</div>

      {/* body */}
      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'flex-start', justifyContent:'space-between', gap:8}}>
          <div style={{flex:1, minWidth:0}}>
            <div style={{
              fontSize:15.5, fontWeight:700, color:UC.text,
              letterSpacing:-0.2, lineHeight:1.2,
              whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
            }}>{name}</div>
            <div style={{
              fontSize:12.5, color:UC.muted, marginTop:3, fontWeight:500,
              whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
            }}>
              {prof} · {schedule}
            </div>
          </div>
          {grade !== undefined && (
            <div style={{
              textAlign:'right', flexShrink:0,
            }}>
              <div style={{fontSize:11, color:UC.muted, fontWeight:600, letterSpacing:0.4}}>NOTA</div>
              <div style={{fontSize:17, fontWeight:700, color:UC.text, letterSpacing:-0.3, lineHeight:1, marginTop:2}}>
                {grade}
              </div>
            </div>
          )}
        </div>

        {/* chips */}
        <div style={{display:'flex', gap:6, marginTop:10, flexWrap:'wrap'}}>
          {deliveries && (
            <Chip color={deliveries.urgent ? UC.red : UC.muted} icon={ui.doc}
              tone={deliveries.urgent ? 'tinted' : 'plain'}>
              {deliveries.label}
            </Chip>
          )}
          {exam && (
            <Chip color={exam.color || UC.amber} icon={ui.exam}
              tone={exam.tone || 'tinted'}>
              {exam.label}
            </Chip>
          )}
        </div>
      </div>
    </a>
  );
}

function Chip({children, icon, color, tone='plain'}) {
  const tinted = tone === 'tinted';
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:5,
      padding:'4px 9px', borderRadius:8,
      background: tinted ? hexA(color, 0.14) : 'rgba(255,255,255,0.04)',
      border: tinted ? `1px solid ${hexA(color, 0.32)}` : '1px solid transparent',
      color: tinted ? color : UC.muted,
      fontSize:11.5, fontWeight:600, letterSpacing:0.1,
    }}>
      {icon}{children}
    </span>
  );
}

// ── Section header ─────────────────────────────────────────────
function SectionHeader({label, count, action}) {
  return (
    <div style={{
      display:'flex', alignItems:'baseline', justifyContent:'space-between',
      padding:'18px 22px 4px',
    }}>
      <div style={{display:'flex', alignItems:'baseline', gap:8}}>
        <span style={{fontSize:15, fontWeight:700, color:UC.text, letterSpacing:-0.2}}>
          {label}
        </span>
        {count !== undefined && (
          <span style={{fontSize:12, color:UC.muted, fontWeight:600}}>{count}</span>
        )}
      </div>
      {action && (
        <span style={{fontSize:12, color:UC.accent, fontWeight:600}}>{action}</span>
      )}
    </div>
  );
}

// ── FAB ────────────────────────────────────────────────────────
function FAB() {
  return (
    <div style={{
      position:'absolute', right:18, bottom:96,
      width:60, height:60, borderRadius:'50%',
      background: UC.accent, color:'#fff',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)',
    }}>{ui.mic}</div>
  );
}

// ── Bottom nav ─────────────────────────────────────────────────
function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ui.home},
    {key:'tasks', label:'Tareas', icon:ui.tasks},
    {key:'cal', label:'Calendario', icon:ui.cal},
    {key:'uni', label:'Universidad', icon:ui.uni, active:true},
    {key:'notes', label:'Apuntes', icon:ui.notes},
  ];
  return (
    <div style={{
      background: UC.bg,
      borderTop: `1px solid ${UC.hairline}`,
      padding:'10px 8px 8px',
      display:'flex', justifyContent:'space-around',
    }}>
      {items.map(it => (
        <div key={it.key} style={{
          display:'flex', flexDirection:'column', alignItems:'center', gap:4,
          flex:1, padding:'4px 0',
          color: it.active ? UC.accent : UC.muted,
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
function UniversidadScreen() {
  return (
    <div style={{
      background: UC.bg, color: UC.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <SummaryCard/>

        <SectionHeader label="Mis cursos" count="4" action="Ver archivo"/>

        <CourseCard
          color={UC.accent}
          initial="C"
          name="Cálculo III"
          prof="Prof. Mendoza"
          schedule="Lun y Mié · 2:00 pm"
          grade="15.8"
          deliveries={{label:'2 entregas', urgent:true}}
          exam={{label:'Examen en 2 días', color:UC.amber}}
        />

        <CourseCard
          color={UC.green}
          initial="E"
          name="Estadística II"
          prof="Prof. Vargas"
          schedule="Mar y Jue · 10:00 am"
          grade="17.2"
          deliveries={{label:'1 entrega vencida', urgent:true}}
          exam={{label:'Parcial en 9 días', color:UC.green, tone:'tinted'}}
        />

        <CourseCard
          color={UC.amber}
          initial="S"
          name="Sistemas de Información"
          prof="Prof. Ríos"
          schedule="Mié y Vie · 4:00 pm"
          grade="16.0"
          deliveries={{label:'3 lecturas', urgent:false}}
          exam={{label:'Sin examen próximo', color:UC.muted, tone:'plain'}}
        />

        <CourseCard
          color={UC.purple}
          initial="F"
          name="Filosofía de la Ciencia"
          prof="Prof. Aguirre"
          schedule="Vie · 6:00 pm"
          grade="16.5"
          deliveries={{label:'1 ensayo', urgent:false}}
          exam={{label:'Final en 4 semanas', color:UC.purple, tone:'tinted'}}
        />
      </div>

      <MatixFAB/>
      <MatixBottomNav active="uni"/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <UniversidadScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
