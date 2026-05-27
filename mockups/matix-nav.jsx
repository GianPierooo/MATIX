// Matix — Shared bottom nav + FAB
// Loads BEFORE every screen's jsx so they can use <MatixBottomNav active=".."/>

(function(){
  const C = {
    bg:'#0B0F1A', card:'#161B2E',
    accent:'#2D7FF9', purple:'#9B7BFF',
    text:'#E8ECF4', muted:'#8A93A8',
    hairline:'rgba(255,255,255,0.06)',
  };
  const hexA = (hex,a) => {
    const h=hex.replace('#','');
    return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
  };

  // Inline SVG icons
  const ICONS = {
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
    matix: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/>
      </svg>
    ),
    projects: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M5 22V4"/>
        <path d="M5 4h12l-2.5 4.5L17 13H5"/>
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
    mic: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        <rect x="9" y="3" width="6" height="12" rx="3"/>
        <path d="M5 11a7 7 0 0 0 14 0"/>
        <path d="M12 18v3"/>
      </svg>
    ),
  };

  // Barra inferior: Inicio · Proyectos · Matix (centro) · Tareas · Universidad.
  // Apuntes y Calendario NO viven en el nav. Apuntes se accede desde
  // Universidad y desde Proyectos; Calendario desde Inicio (header + "Ver
  // agenda" en el bloque "Tu día"). El icono `notes` queda definido arriba
  // para esos enlaces secundarios.
  const ITEMS = [
    {key:'home',     label:'Inicio',      href:'Inicio.html',       icon: ICONS.home},
    {key:'projects', label:'Proyectos',   href:'Proyectos.html',    icon: ICONS.projects},
    {key:'matix',    label:'Matix',       href:'Matix%20Chat.html', icon: ICONS.matix, center:true},
    {key:'tasks',    label:'Tareas',      href:'Tareas.html',       icon: ICONS.tasks},
    {key:'uni',      label:'Universidad', href:'Universidad.html',  icon: ICONS.uni},
  ];

  function NavItem({it, active}) {
    if (it.center) {
      // Elevated Matix button
      return (
        <a href={it.href} style={{
          flex:1, display:'flex', flexDirection:'column', alignItems:'center',
          textDecoration:'none', position:'relative',
          marginTop:-22,
        }}>
          <div style={{
            width:54, height:54, borderRadius:'50%',
            background: `linear-gradient(135deg, ${C.accent} 0%, ${C.purple} 100%)`,
            color:'#fff',
            display:'flex', alignItems:'center', justifyContent:'center',
            boxShadow:`0 12px 28px ${hexA(C.accent,0.50)}, 0 0 0 5px ${C.bg}, 0 0 0 6px ${hexA(C.accent,0.18)}`,
          }}>{it.icon}</div>
          <span style={{
            fontSize:10.5, fontWeight:700, letterSpacing:0.2,
            color: active ? C.accent : C.muted, marginTop:5,
          }}>{it.label}</span>
        </a>
      );
    }
    return (
      <a href={it.href} style={{
        flex:1, display:'flex', flexDirection:'column', alignItems:'center', gap:4,
        padding:'4px 0', color: active?C.accent:C.muted, textDecoration:'none',
      }}>
        {active ? (
          <div style={{
            padding:'4px 14px', borderRadius:999,
            background:'rgba(45,127,249,0.16)',
            display:'flex', alignItems:'center', justifyContent:'center',
          }}>{it.icon}</div>
        ) : it.icon}
        <span style={{
          fontSize:10.5, fontWeight: active?600:500, letterSpacing:0.1,
        }}>{it.label}</span>
      </a>
    );
  }

  function MatixBottomNav({active}) {
    return (
      <div style={{
        background: C.bg,
        borderTop: `1px solid ${C.hairline}`,
        padding:'10px 8px 8px',
        display:'flex', justifyContent:'space-around', alignItems:'flex-end',
      }}>
        {ITEMS.map(it => (
          <NavItem key={it.key} it={it} active={active === it.key}/>
        ))}
      </div>
    );
  }

  function MatixFAB({href = 'Matix%20Escuchando.html'}) {
    return (
      <a href={href} style={{
        position:'absolute', right:18, bottom:96,
        width:56, height:56, borderRadius:'50%',
        background: C.card, color: C.text,
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 10px 24px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.05) inset',
        textDecoration:'none',
      }}>{ICONS.mic}</a>
    );
  }

  Object.assign(window, { MatixBottomNav, MatixFAB });
})();
