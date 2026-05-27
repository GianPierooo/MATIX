// Matix — Inicio (panel del día)

const IN = {
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

// ── Icons ─────────────────────────────────────────────────────
const ii = {
  spark: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2.5l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/>
    </svg>
  ),
  sparkSm: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2.5l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/>
    </svg>
  ),
  check: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12.5 10 17 19 7.5"/>
    </svg>
  ),
  clock: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
    </svg>
  ),
  mic: (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>
    </svg>
  ),
  arrow: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6"/>
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

// ── Top bar / greeting ────────────────────────────────────────
function Greeting() {
  return (
    <div style={{
      display:'flex', alignItems:'flex-start', justifyContent:'space-between',
      padding:'16px 20px 8px',
    }}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{
          fontSize:13, color:IN.muted, fontWeight:500, letterSpacing:0.1,
        }}>
          Martes, 26 de mayo
        </span>
        <span style={{
          fontSize:26, color:IN.text, fontWeight:700, letterSpacing:-0.5, marginTop:2, lineHeight:1.1,
        }}>
          Buenos días, Gian Piero
        </span>
      </div>
      {/* Quick actions: search, calendar, notes, cierre, settings */}
      <div style={{display:'flex', alignItems:'center', gap:6, marginTop:2}}>
        {/* Search */}
        <a href="Busqueda.html" style={{
          width:36, height:36, borderRadius:10,
          background: IN.card, color: IN.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
          textDecoration:'none', flexShrink:0,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>
          </svg>
        </a>
        {/* Calendar */}
        <a href="Calendario.html" style={{
          width:36, height:36, borderRadius:10,
          background: IN.card, color: IN.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
          textDecoration:'none', flexShrink:0,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3.5" y="5" width="17" height="15" rx="2.5"/>
            <path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/>
          </svg>
        </a>
        {/* Notes */}
        <a href="Apuntes.html" style={{
          width:36, height:36, borderRadius:10,
          background: IN.card, color: IN.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
          textDecoration:'none', flexShrink:0,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/>
            <path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/>
          </svg>
        </a>
        {/* Cierre del día (luna) */}
        <a href="Cierre%20Dia.html" style={{
          width:36, height:36, borderRadius:10,
          background: IN.card, color: IN.muted,
          display:'flex', alignItems:'center', justifyContent:'center',
          textDecoration:'none', flexShrink:0,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/>
          </svg>
        </a>
        {/* Ajustes */}
        <a href="Ajustes.html" style={{
          width:36, height:36, borderRadius:10,
          background:`linear-gradient(135deg, ${IN.accent}, #9B7BFF)`,
          color:'#fff', display:'flex', alignItems:'center', justifyContent:'center',
          fontSize:11.5, fontWeight:700, letterSpacing:-0.3,
          boxShadow:`0 4px 12px ${hexA(IN.accent,0.35)}`,
          textDecoration:'none', flexShrink:0,
        }}>GP</a>
      </div>
    </div>
  );
}

// ── Matix summary card ────────────────────────────────────────
function MatixCard() {
  return (
    <div style={{
      margin:'10px 16px 6px',
      background: IN.card,
      borderRadius:18,
      padding:'16px 16px 14px',
      border: `1px solid ${hexA(IN.accent, 0.35)}`,
      position:'relative', overflow:'hidden',
    }}>
      {/* corner glow */}
      <div style={{
        position:'absolute', top:-40, right:-30, width:160, height:160,
        background: `radial-gradient(circle, ${hexA(IN.accent, 0.18)} 0%, transparent 70%)`,
        pointerEvents:'none',
      }}/>

      <div style={{position:'relative'}}>
        <div style={{
          display:'inline-flex', alignItems:'center', gap:6,
          padding:'3px 9px 3px 8px', borderRadius:99,
          background: hexA(IN.accent, 0.16),
          color: IN.accent, fontSize:10.5, fontWeight:700, letterSpacing:1.2,
        }}>
          {ii.sparkSm}<span>MATIX</span>
        </div>

        <div style={{
          marginTop:11, fontSize:15.5, lineHeight:1.5,
          color: IN.text, fontWeight:500, letterSpacing:-0.1,
          textWrap:'pretty',
        }}>
          Hoy <span style={{fontWeight:700}}>Gobierno de TIC 8:30</span> y
          <span style={{fontWeight:700}}> Continuidad 18:30</span>. Pasaste
          5 días sin tocar <span style={{color:IN.red, fontWeight:700}}>
          Shadows Games</span> — está en riesgo.
        </div>

        <div style={{
          marginTop:14, display:'flex', alignItems:'center', gap:8,
        }}>
          <a href="Matix%20Chat.html" style={{
            display:'inline-flex', alignItems:'center', gap:6,
            padding:'7px 12px', borderRadius:10,
            background: IN.accent, color:'#fff',
            fontSize:12.5, fontWeight:600, textDecoration:'none',
            boxShadow:'0 4px 12px rgba(45,127,249,0.30)',
          }}>
            Ver plan del día {ii.arrow}
          </a>
          <a href="Matix%20Chat.html" style={{
            display:'inline-flex', alignItems:'center', gap:6,
            padding:'7px 12px', borderRadius:10,
            background:'rgba(255,255,255,0.04)',
            color: IN.text, fontSize:12.5, fontWeight:600, textDecoration:'none',
          }}>
            Pregunta a Matix
          </a>
        </div>
      </div>
    </div>
  );
}

// ── Section header ────────────────────────────────────────────
function Section({label, count, action, actionHref}) {
  return (
    <div style={{
      display:'flex', alignItems:'baseline', justifyContent:'space-between',
      padding:'18px 22px 4px',
    }}>
      <div style={{display:'flex', alignItems:'baseline', gap:8}}>
        <span style={{fontSize:15, fontWeight:700, color:IN.text, letterSpacing:-0.2}}>
          {label}
        </span>
        {count !== undefined && (
          <span style={{fontSize:12, color:IN.muted, fontWeight:600}}>{count}</span>
        )}
      </div>
      {action && (
        <a href={actionHref || '#'} style={{fontSize:12, color:IN.accent, fontWeight:600, textDecoration:'none'}}>{action}</a>
      )}
    </div>
  );
}

// ── Task row ──────────────────────────────────────────────────
function TaskRow({title, meta, time, priority, done}) {
  const prColor = priority === 'high' ? IN.red : priority === 'med' ? IN.amber : IN.accent;
  return (
    <a href="Detalle%20Tarea.html" style={{
      margin:'6px 16px',
      padding:'12px 14px',
      background: IN.card,
      border: '1px solid rgba(255,255,255,0.03)',
      borderRadius:14,
      display:'flex', alignItems:'flex-start', gap:12,
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{
        width:22, height:22, borderRadius:'50%',
        background: done ? IN.green : 'transparent',
        border: done ? 'none' : '1.8px solid rgba(255,255,255,0.18)',
        display:'flex', alignItems:'center', justifyContent:'center',
        flexShrink:0, marginTop:1,
      }}>
        {done && ii.check}
      </div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'center', gap:8}}>
          <span style={{
            width:7, height:7, borderRadius:'50%', background:prColor, flexShrink:0,
          }}/>
          <span style={{
            fontSize:14.5, fontWeight:600, color: done ? IN.muted : IN.text,
            textDecoration: done ? 'line-through' : 'none',
            letterSpacing:-0.1, lineHeight:1.25,
          }}>{title}</span>
        </div>
        <div style={{
          display:'flex', alignItems:'center', gap:8, marginTop:5,
          fontSize:12, color: IN.muted,
        }}>
          <span style={{
            display:'inline-flex', alignItems:'center', gap:4,
            padding:'2px 7px', borderRadius:6,
            background:'rgba(255,255,255,0.04)', color:IN.muted, fontWeight:500,
          }}>{meta}</span>
          <span style={{display:'inline-flex', alignItems:'center', gap:4}}>
            {ii.clock}<span style={{fontWeight:500}}>{time}</span>
          </span>
        </div>
      </div>
    </a>
  );
}

// ── Delivery card ─────────────────────────────────────────────
function Delivery({course, courseColor, name, dueChip, dueColor}) {
  return (
    <a href="Detalle%20Tarea.html" style={{
      margin:'6px 16px',
      padding:'14px 14px',
      background: IN.card,
      border:'1px solid rgba(255,255,255,0.03)',
      borderRadius:14,
      display:'flex', alignItems:'flex-start', gap:12,
      textDecoration:'none', color:'inherit',
    }}>
      {/* course dot column */}
      <div style={{
        width:36, height:36, borderRadius:10,
        background: hexA(courseColor, 0.14),
        border: `1px solid ${hexA(courseColor, 0.45)}`,
        color: courseColor,
        display:'flex', alignItems:'center', justifyContent:'center',
        fontSize:14, fontWeight:700, letterSpacing:-0.3,
        flexShrink:0,
      }}>{course[0]}</div>

      <div style={{flex:1, minWidth:0}}>
        <div style={{
          fontSize:11, fontWeight:600, color:courseColor,
          letterSpacing:0.4, textTransform:'uppercase',
        }}>{course}</div>
        <div style={{
          fontSize:14.5, fontWeight:600, color:IN.text, marginTop:3,
          letterSpacing:-0.15, lineHeight:1.25,
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
        }}>{name}</div>
      </div>

      <div style={{
        display:'inline-flex', alignItems:'center', gap:5,
        padding:'4px 9px', borderRadius:8,
        background: hexA(dueColor, 0.14),
        border: `1px solid ${hexA(dueColor, 0.35)}`,
        color: dueColor, fontSize:11.5, fontWeight:700,
        whiteSpace:'nowrap', flexShrink:0, marginTop:2,
      }}>
        {ii.clock}<span>{dueChip}</span>
      </div>
    </a>
  );
}

// ── Day event row ─────────────────────────────────────────────
function DayEvent({time, endTime, color, title, sub}) {
  return (
    <a href="Detalle%20Evento.html" style={{
      display:'flex', alignItems:'stretch', gap:14,
      padding:'8px 18px 8px',
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{
        width:48, flexShrink:0, paddingTop:2,
        display:'flex', flexDirection:'column', alignItems:'flex-end',
      }}>
        <span style={{fontSize:13, fontWeight:600, color:IN.text, letterSpacing:0.2}}>{time}</span>
        {endTime && <span style={{fontSize:10.5, color:IN.muted, marginTop:1}}>{endTime}</span>}
      </div>
      <div style={{
        width:4, borderRadius:4, background:color, flexShrink:0,
        boxShadow:`0 0 12px ${hexA(color, 0.45)}`,
      }}/>
      <div style={{
        flex:1, minWidth:0,
        background: IN.card,
        borderRadius:14,
        padding:'10px 14px',
      }}>
        <div style={{fontSize:14, fontWeight:600, color:IN.text, letterSpacing:-0.1, lineHeight:1.2}}>{title}</div>
        <div style={{fontSize:12, color:IN.muted, marginTop:3, fontWeight:500}}>{sub}</div>
      </div>
    </a>
  );
}

// ── FAB ───────────────────────────────────────────────────────
function FAB() {
  return (
    <div style={{
      position:'absolute', right:18, bottom:96,
      width:60, height:60, borderRadius:'50%',
      background: IN.accent, color:'#fff',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)',
    }}>{ii.mic}</div>
  );
}

// ── Active-project mini card (horizontal scroller on home) ─────
function ProyectoMini({prioridad, nombre, color, accion, calor}) {
  const calorColor = calor.tono === 'rojo' ? IN.red
    : calor.tono === 'amber' ? IN.amber
    : IN.green;
  return (
    <a href="Detalle%20Proyecto.html" style={{
      flexShrink:0,
      width: 228,
      padding:'12px 12px 11px',
      background: IN.card,
      border: `1px solid ${hexA(color, 0.35)}`,
      borderRadius: 14,
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{display:'flex', alignItems:'center', gap:8}}>
        <div style={{
          width:24, height:24, borderRadius:8,
          background: hexA(color, 0.18),
          border: `1px solid ${hexA(color, 0.45)}`,
          color: color,
          display:'flex', alignItems:'center', justifyContent:'center',
          fontSize:11, fontWeight:800, letterSpacing:-0.3,
        }}>#{prioridad}</div>
        <span style={{
          flex:1, fontSize:14, fontWeight:700, color: IN.text,
          letterSpacing:-0.2,
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
        }}>{nombre}</span>
        <span style={{
          fontSize:10, fontWeight:700,
          padding:'2px 6px', borderRadius:6,
          background: hexA(calorColor, 0.14),
          border: `1px solid ${hexA(calorColor, 0.30)}`,
          color: calorColor,
          whiteSpace:'nowrap',
        }}>{calor.label}</span>
      </div>
      <div style={{
        marginTop:9, padding:'7px 9px',
        background: hexA(color, 0.10),
        borderRadius: 9,
        fontSize:11, fontWeight:600, color: color,
        letterSpacing:0.5, textTransform:'uppercase',
      }}>SIGUIENTE</div>
      <div style={{
        marginTop:5, fontSize:12.5, color: IN.text, fontWeight:500,
        lineHeight:1.35,
        display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical',
        overflow:'hidden',
      }}>{accion}</div>
    </a>
  );
}

// ── Screen ────────────────────────────────────────────────────
// Nota: la barra inferior canónica vive en `matix-nav.jsx`
// (<MatixBottomNav/>). Se eliminó una función `BottomNav()` local que
// estaba aquí pero no se usaba — confundía la fuente de verdad.
function InicioScreen() {
  return (
    <div style={{
      background: IN.bg, color: IN.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <Greeting/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <MatixCard/>

        <Section label="Tus 3 proyectos activos" action="Ver todos" actionHref="Proyectos.html"/>
        <div style={{
          display:'flex', gap:10, padding:'4px 16px 6px',
          overflowX:'auto',
        }}>
          <ProyectoMini
            prioridad={1} nombre="Matix" color={IN.accent}
            accion="Validar Tareas en el teléfono"
            calor={{label:'Hoy', tono:'verde'}}
          />
          <ProyectoMini
            prioridad={2} nombre="OnExotic" color={IN.purple}
            accion="Subir fotos del último drop"
            calor={{label:'Hace 2d', tono:'amber'}}
          />
          <ProyectoMini
            prioridad={3} nombre="Shadows Games" color={IN.green}
            accion="Cerrar alcance jam con Leo"
            calor={{label:'5d · RIESGO', tono:'rojo'}}
          />
        </div>

        <Section label="Para hoy" count="3" action="Ver todas" actionHref="Tareas.html"/>
        <TaskRow
          title="Validar pantalla de Tareas en el teléfono"
          meta="Matix #1" time="11:00"
          priority="med"
        />
        <TaskRow
          title="Subir fotos del último drop a la tienda"
          meta="OnExotic #2" time="18:30"
          priority="high"
        />
        <TaskRow
          title="Calistenia matutina"
          meta="Personal" time="—"
          priority="low" done
        />

        <Section label="Próximas entregas" count="2" action="Ver todas" actionHref="Universidad.html"/>
        <Delivery
          course="Calidad de Software" courseColor={IN.green}
          name="Examen parcial"
          dueChip="Mié · 18:30" dueColor={IN.red}
        />
        <Delivery
          course="Gobierno de TIC" courseColor={IN.purple}
          name="Ensayo entrega 2"
          dueChip="Jue · 23:59" dueColor={IN.amber}
        />

        <Section label="Tu día" count="3" action="Ver agenda" actionHref="Calendario.html"/>
        <DayEvent
          time="08:30" endTime="10:00"
          color={IN.purple}
          title="Gobierno de TIC — Clase"
          sub="Sesión semanal"
        />
        <DayEvent
          time="18:30" endTime="20:00"
          color={IN.red}
          title="Gestión de la Continuidad del Negocio — Clase"
          sub="Sesión semanal"
        />
        <DayEvent
          time="21:00" endTime="22:00"
          color={IN.amber}
          title="Box · Vinces Fight SMP"
          sub="Rutina anclada"
        />
      </div>

      <MatixFAB/>
      <MatixBottomNav active="home"/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <InicioScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
