// Matix — Nueva tarea (crear)

const NT = {
  bg: '#0B0F1A',
  card: '#161B2E',
  cardHi: '#1B2138',
  accent: '#2D7FF9',
  green: '#21D07A',
  red: '#FF4D5E',
  amber: '#E0A33A',
  text: '#E8ECF4',
  muted: '#8A93A8',
  hairline: 'rgba(255,255,255,0.07)',
};

// ── Icons ──────────────────────────────────────────────────────
const ni = {
  close: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round">
      <path d="M6 6l12 12M18 6 6 18"/>
    </svg>
  ),
  calendar: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="5" width="17" height="15" rx="2.5"/>
      <path d="M3.5 10h17"/>
      <path d="M8 3v4M16 3v4"/>
    </svg>
  ),
  flag: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 21V4"/>
      <path d="M5 4h12l-2 4 2 4H5"/>
    </svg>
  ),
  projects: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 22V4"/>
      <path d="M5 4h12l-2.5 4.5L17 13H5"/>
    </svg>
  ),
  folder: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3.5 7a1.5 1.5 0 0 1 1.5-1.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v9a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 18V7z"/>
    </svg>
  ),
  repeat: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12a8 8 0 0 1 14-5.3L20 9"/>
      <path d="M20 5v4h-4"/>
      <path d="M20 12a8 8 0 0 1-14 5.3L4 15"/>
      <path d="M4 19v-4h4"/>
    </svg>
  ),
  note: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 4.5h11l3.5 3.5V19a.5.5 0 0 1-.5.5H5a.5.5 0 0 1-.5-.5V5a.5.5 0 0 1 .5-.5z"/>
      <path d="M7.5 10h9M7.5 13.5h9M7.5 17h5"/>
    </svg>
  ),
  list: (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 7h2M4 12h2M4 17h2"/>
      <path d="M9 7h11M9 12h11M9 17h7"/>
    </svg>
  ),
  chev: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 6l6 6-6 6"/>
    </svg>
  ),
  plusSmall: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  drag: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="9" cy="6" r="1.6"/><circle cx="15" cy="6" r="1.6"/>
      <circle cx="9" cy="12" r="1.6"/><circle cx="15" cy="12" r="1.6"/>
      <circle cx="9" cy="18" r="1.6"/><circle cx="15" cy="18" r="1.6"/>
    </svg>
  ),
};

// ── Top bar ────────────────────────────────────────────────────
function NTTopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 18px 8px', position:'relative',
    }}>
      <a href="Tareas.html" style={{
        width:40, height:40, borderRadius:12,
        background:NT.card, color:NT.text,
        display:'flex', alignItems:'center', justifyContent:'center',
        textDecoration:'none',
      }}>{ni.close}</a>
      <div style={{
        position:'absolute', left:0, right:0, textAlign:'center',
        pointerEvents:'none',
      }}>
        <span style={{fontSize:16, fontWeight:600, color:NT.text, letterSpacing:-0.1}}>
          Nueva tarea
        </span>
      </div>
      <div style={{width:40, height:40}}/>
    </div>
  );
}

// ── Title input ────────────────────────────────────────────────
function TitleInput() {
  return (
    <div style={{padding:'14px 22px 18px'}}>
      <div style={{
        fontSize:22, fontWeight:600, letterSpacing:-0.5,
        color:NT.text, lineHeight:1.25,
      }}>
        <span>Entregar informe final</span>
        <span style={{
          display:'inline-block', width:2, height:24,
          background:NT.accent, marginLeft:2, verticalAlign:'-4px',
          animation:'blink 1.1s steps(1) infinite',
        }}/>
      </div>
      <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>
      <div style={{
        marginTop:4, fontSize:13, color:NT.muted,
      }}>
        ¿Qué tienes que hacer?
      </div>
    </div>
  );
}

// ── Field row (icon + label + value) ───────────────────────────
function FieldRow({icon, label, children, last, accent}) {
  return (
    <div style={{
      display:'flex', alignItems:'flex-start', gap:14,
      padding:'14px 20px',
      borderBottom: last ? 'none' : `1px solid ${NT.hairline}`,
    }}>
      <div style={{
        width:36, height:36, borderRadius:10,
        background: accent ? 'rgba(45,127,249,0.14)' : 'rgba(255,255,255,0.04)',
        color: accent ? NT.accent : NT.muted,
        display:'flex', alignItems:'center', justifyContent:'center',
        flexShrink:0,
      }}>{icon}</div>
      <div style={{flex:1, minWidth:0, paddingTop:2}}>
        <div style={{fontSize:11, fontWeight:600, color:NT.muted, letterSpacing:0.6, textTransform:'uppercase'}}>
          {label}
        </div>
        <div style={{marginTop:6}}>{children}</div>
      </div>
    </div>
  );
}

// ── Selector value ─────────────────────────────────────────────
function Selector({children, placeholder, chev=true, color}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:8,
      color: color || (children ? NT.text : NT.muted),
      fontSize:15, fontWeight:500,
    }}>
      <span style={{flex:1}}>{children || placeholder}</span>
      {chev && <span style={{color:NT.muted}}>{ni.chev}</span>}
    </div>
  );
}

// ── Priority pills ─────────────────────────────────────────────
function PriorityPills() {
  const opts = [
    {key:'high', label:'Alta', color:NT.red},
    {key:'med', label:'Media', color:NT.amber, active:true},
    {key:'low', label:'Baja', color:NT.accent},
  ];
  return (
    <div style={{display:'flex', gap:8}}>
      {opts.map(o => (
        <div key={o.key} style={{
          flex:1, padding:'9px 0', borderRadius:10,
          display:'flex', alignItems:'center', justifyContent:'center', gap:7,
          background: o.active ? `${hexAlpha(o.color, 0.14)}` : 'rgba(255,255,255,0.03)',
          border: o.active ? `1px solid ${hexAlpha(o.color, 0.55)}` : '1px solid transparent',
          color: o.active ? o.color : NT.muted,
          fontSize:13, fontWeight:600,
        }}>
          <span style={{
            width:7, height:7, borderRadius:'50%', background:o.color,
          }}/>
          {o.label}
        </div>
      ))}
    </div>
  );
}

function hexAlpha(hex, a) {
  const h = hex.replace('#','');
  const r = parseInt(h.slice(0,2),16), g = parseInt(h.slice(2,4),16), b = parseInt(h.slice(4,6),16);
  return `rgba(${r},${g},${b},${a})`;
}

// ── Category chip ──────────────────────────────────────────────
function CategoryChip() {
  return (
    <div style={{display:'flex', alignItems:'center', gap:8}}>
      <div style={{
        display:'inline-flex', alignItems:'center', gap:8,
        padding:'6px 11px 6px 8px', borderRadius:999,
        background: hexAlpha(NT.accent, 0.14),
        border: `1px solid ${hexAlpha(NT.accent, 0.35)}`,
        color: NT.accent, fontSize:13, fontWeight:600,
      }}>
        <span style={{
          width:8, height:8, borderRadius:'50%', background:NT.accent,
        }}/>
        Estadística II
      </div>
      <span style={{flex:1}}/>
      <span style={{color:NT.muted}}>{ni.chev}</span>
    </div>
  );
}

// ── Note textarea look ─────────────────────────────────────────
function NoteField() {
  return (
    <div style={{
      background:'rgba(255,255,255,0.03)',
      border:`1px solid ${NT.hairline}`,
      borderRadius:12, padding:'10px 12px',
      color: NT.muted, fontSize:14, lineHeight:1.5,
      minHeight:64,
    }}>
      Añade detalles, links o material a revisar…
    </div>
  );
}

// ── Subtask row ────────────────────────────────────────────────
function Subtask({title, done}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:12,
      padding:'10px 12px',
      borderRadius:12,
      background:'rgba(255,255,255,0.025)',
      marginBottom:6,
    }}>
      <span style={{color:NT.muted, opacity:0.6}}>{ni.drag}</span>
      <div style={{
        width:18, height:18, borderRadius:'50%',
        background: done ? NT.green : 'transparent',
        border: done ? 'none' : '1.6px solid rgba(255,255,255,0.22)',
        display:'flex', alignItems:'center', justifyContent:'center',
        flexShrink:0,
      }}>
        {done && (
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 12.5 10 17 19 7.5"/>
          </svg>
        )}
      </div>
      <span style={{
        flex:1, fontSize:14, fontWeight:500,
        color: done ? NT.muted : NT.text,
        textDecoration: done ? 'line-through' : 'none',
      }}>{title}</span>
    </div>
  );
}

// ── Section header (small) ─────────────────────────────────────
function SectionLabel({children, count}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:8,
      padding:'18px 22px 8px',
    }}>
      <span style={{
        fontSize:11, fontWeight:600, letterSpacing:0.8,
        color:NT.muted, textTransform:'uppercase',
      }}>{children}</span>
      {count !== undefined && (
        <span style={{
          fontSize:11, fontWeight:600, color:NT.muted, opacity:0.55,
        }}>{count}</span>
      )}
      <div style={{flex:1, height:1, background:NT.hairline, marginLeft:4}}/>
    </div>
  );
}

// ── Screen ─────────────────────────────────────────────────────
function NuevaTareaScreen() {
  return (
    <div style={{
      background:NT.bg, color:NT.text, height:'100%',
      display:'flex', flexDirection:'column',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <NTTopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:120}}>
        <TitleInput/>

        {/* Card with field rows */}
        <div style={{
          margin:'4px 16px 0',
          background:NT.card,
          borderRadius:18,
          overflow:'hidden',
        }}>
          <a href="Selector%20Fecha.html" style={{textDecoration:'none', color:'inherit', display:'block'}}><FieldRow icon={ni.calendar} label="Fecha y hora límite" accent>
            <div style={{display:'flex', alignItems:'center', gap:8}}>
              <span style={{fontSize:15, fontWeight:600, color:NT.text}}>
                Vie 30 mayo
              </span>
              <span style={{
                width:3, height:3, borderRadius:'50%', background:NT.muted,
                margin:'0 2px',
              }}/>
              <span style={{fontSize:15, fontWeight:500, color:NT.text}}>
                23:59
              </span>
              <span style={{flex:1}}/>
              <span style={{color:NT.muted}}>{ni.chev}</span>
            </div>
          </FieldRow></a>

          <FieldRow icon={ni.flag} label="Prioridad">
            <PriorityPills/>
          </FieldRow>

          <FieldRow icon={ni.folder} label="Curso o categoría">
            <CategoryChip/>
          </FieldRow>

          <FieldRow icon={ni.projects} label="Proyecto">
            <Selector>Sin proyecto</Selector>
          </FieldRow>

          <FieldRow icon={ni.repeat} label="Repetición" last>
            <Selector>No se repite</Selector>
          </FieldRow>
        </div>

        {/* Note card */}
        <div style={{margin:'14px 16px 0', background:NT.card, borderRadius:18, overflow:'hidden'}}>
          <FieldRow icon={ni.note} label="Nota" last>
            <NoteField/>
          </FieldRow>
        </div>

        {/* Subtasks */}
        <SectionLabel count="2">Subtareas</SectionLabel>
        <div style={{padding:'0 16px'}}>
          <Subtask title="Recopilar datos del trimestre"/>
          <Subtask title="Redactar conclusiones" done/>
          <div style={{
            display:'flex', alignItems:'center', gap:8,
            padding:'12px 12px', marginTop:2,
            color:NT.accent, fontSize:14, fontWeight:600,
          }}>
            {ni.plusSmall}
            <span>Añadir subtarea</span>
          </div>
        </div>
      </div>

      {/* Footer save button */}
      <div style={{
        padding:'12px 16px 18px',
        background:`linear-gradient(180deg, rgba(11,15,26,0) 0%, ${NT.bg} 30%)`,
      }}>
        <div style={{
          padding:'15px 0', borderRadius:14,
          background:NT.accent, color:'#fff',
          display:'flex', alignItems:'center', justifyContent:'center',
          fontSize:15, fontWeight:700, letterSpacing:0.1,
          boxShadow:'0 12px 28px rgba(45,127,249,0.40), 0 0 0 1px rgba(255,255,255,0.06) inset',
        }}>
          Guardar tarea
        </div>
      </div>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <NuevaTareaScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
