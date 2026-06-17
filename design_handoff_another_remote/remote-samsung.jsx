// Variation D: Direct Samsung-style layout match
// Same button positions, sizes, and proportions as the reference photo.
// Original streaming-app slots (no branded logos).
// Built as ATOMIC components for easy SwiftUI translation.

// ─────────────────────────────────────────────────────────────
// ATOMS — each maps directly to a SwiftUI view
// ─────────────────────────────────────────────────────────────

// SwiftUI: Circle().fill(...).shadow(...) inside a ZStack
const SamsungCircleButton = ({ size, children, accent, style, color = '#dcdcde' }) => (
  <div style={{
    width: size, height: size, borderRadius: '50%',
    position: 'relative',
    background: accent
      ? 'radial-gradient(circle at 35% 30%, #2a2a2e 0%, #1a1a1d 60%, #0e0e10 100%)'
      : 'radial-gradient(circle at 35% 30%, #232327 0%, #161618 60%, #0c0c0e 100%)',
    boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.05), inset 0 -1px 2px rgba(0,0,0,0.6), 0 2px 4px rgba(0,0,0,0.5)',
    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
    color: color,
    ...style,
  }}>
    {children}
  </div>
);

// SwiftUI: ZStack { Capsule().fill(...); HStack/VStack{...} }
const SamsungRocker = ({ width, height, top, bottom, label }) => (
  <div style={{
    width, height, position: 'relative',
    borderRadius: height / 2,
    background: 'radial-gradient(ellipse at 50% 30%, #232327 0%, #161618 60%, #0c0c0e 100%)',
    boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.05), inset 0 -1px 2px rgba(0,0,0,0.6), 0 2px 4px rgba(0,0,0,0.5)',
    display: 'flex', alignItems: 'center', justifyContent: 'space-around',
    color: '#dcdcde',
  }}>
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 1 }}>{top}</div>
    {label && (
      <div style={{
        position: 'absolute', left: '50%', top: '50%',
        transform: 'translate(-50%, -50%)',
        fontSize: 8, fontWeight: 700, letterSpacing: 1.2,
        color: '#3a3a3e',
      }}>{label}</div>
    )}
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 1 }}>{bottom}</div>
  </div>
);

// SwiftUI: ZStack with concentric Circles
const SamsungDPad = ({ outerSize, innerSize }) => (
  <div style={{
    width: outerSize, height: outerSize, position: 'relative',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  }}>
    {/* Outer ring */}
    <div style={{
      position: 'absolute', inset: 0, borderRadius: '50%',
      background: 'radial-gradient(circle at 50% 25%, #1f1f22 0%, #131316 70%, #0a0a0c 100%)',
      boxShadow: 'inset 0 2px 3px rgba(255,255,255,0.04), inset 0 -2px 4px rgba(0,0,0,0.6), 0 3px 8px rgba(0,0,0,0.6)',
    }} />
    {/* Inner button */}
    <div style={{
      width: innerSize, height: innerSize, borderRadius: '50%',
      background: 'radial-gradient(circle at 35% 30%, #2c2c30 0%, #1a1a1d 55%, #0c0c0e 100%)',
      boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.08), inset 0 -2px 3px rgba(0,0,0,0.6), 0 2px 6px rgba(0,0,0,0.7)',
      position: 'relative', zIndex: 2,
    }} />
  </div>
);

// SwiftUI: Capsule with subtle border (used for streaming slots)
const SamsungSlot = ({ size, label, sublabel, accent }) => (
  <div style={{
    width: size, height: size, borderRadius: '50%',
    background: 'radial-gradient(circle at 35% 30%, #232327 0%, #161618 60%, #0c0c0e 100%)',
    boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.05), inset 0 -1px 2px rgba(0,0,0,0.6), 0 2px 4px rgba(0,0,0,0.5)',
    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
    fontSize: 9.5, fontWeight: 700, letterSpacing: 0.3,
    color: '#cfcfd2',
    textAlign: 'center',
    lineHeight: 1.05,
    padding: '0 4px',
  }}>
    {label}
    {sublabel && <div style={{ fontSize: 8, fontWeight: 600, opacity: 0.7, marginTop: 1 }}>{sublabel}</div>}
  </div>
);

// ─────────────────────────────────────────────────────────────
// LAYOUT
// Reference dimensions match the Samsung remote photo proportions:
//   Body: 144 wide × 540 tall (remote)
//   Scaled to fit iPhone 16 Pro 393×852 viewport.
//   We center the remote vertically and use generous side padding.
// ─────────────────────────────────────────────────────────────

function RemoteSamsungStyle({ accent = 'red', onSettings }) {
  // Layout constants — these mirror the Samsung remote photo's proportions
  // and translate cleanly to SwiftUI offsets.
  const W = 393;   // iPhone width
  const H = 852;   // iPhone height
  const RW = 220;  // remote body width
  const RH = 720;  // remote body height
  const RX = (W - RW) / 2; // 86.5
  const RY = 80;

  const accentRed = '#e63946';

  return (
    <div style={{
      width: W, height: H, position: 'relative', overflow: 'hidden',
      background: 'radial-gradient(ellipse at 50% 0%, #1a1a1d 0%, #0a0a0b 70%)',
      fontFamily: '-apple-system, "SF Pro Text", system-ui',
      color: '#e8e8ea',
    }}>
      {/* Status bar */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 59,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 28px 8px', fontSize: 16, fontWeight: 600, color: '#fff', zIndex: 30,
      }}>
        <span>9:41</span>
        <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <svg width="17" height="11" viewBox="0 0 17 11" fill="#fff"><rect x="0" y="7" width="3" height="4" rx="0.6"/><rect x="4.5" y="5" width="3" height="6" rx="0.6"/><rect x="9" y="3" width="3" height="8" rx="0.6"/><rect x="13.5" y="0" width="3" height="11" rx="0.6"/></svg>
          <svg width="22" height="11" viewBox="0 0 22 11" fill="none" stroke="#fff" strokeWidth="1"><rect x="1" y="2" width="17" height="7" rx="2"/><rect x="3" y="4" width="13" height="3" rx="0.8" fill="#fff"/><path d="M19.5 4.5v2" strokeWidth="1.5" strokeLinecap="round"/></svg>
        </span>
      </div>

      {/* Settings gear in corner */}
      <button onClick={onSettings} style={{
        position: 'absolute', top: 64, right: 18, zIndex: 30,
        width: 36, height: 36, borderRadius: '50%', border: 'none',
        background: 'rgba(255,255,255,0.04)', color: '#9a9a9e', cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <IconSettings size={16} stroke={1.6} />
      </button>

      {/* REMOTE BODY */}
      <div style={{
        position: 'absolute', left: RX, top: RY, width: RW, height: RH,
        borderRadius: 38,
        background: 'linear-gradient(180deg, #1f1f22 0%, #15151820 50%, #0e0e10 100%)',
        boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.08), inset 0 -1px 2px rgba(0,0,0,0.6), 0 12px 32px rgba(0,0,0,0.6), 0 0 0 1px rgba(0,0,0,0.4)',
      }}>

        {/* Row 1: Power (top-left), MIC label center, Mic button (top-right) */}
        {/* Power */}
        <div style={{ position: 'absolute', left: 22, top: 26 }}>
          <SamsungCircleButton size={36} color={accentRed}>
            <IconPower size={16} stroke={2.4} />
          </SamsungCircleButton>
        </div>
        {/* MIC indicator label between */}
        <div style={{
          position: 'absolute', top: 24, left: '50%', transform: 'translateX(-50%)',
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2,
        }}>
          <div style={{ width: 3, height: 3, borderRadius: '50%', background: '#2a2a2e' }} />
          <div style={{ fontSize: 8, fontWeight: 700, letterSpacing: 1, color: '#5a5a5e' }}>MIC</div>
        </div>
        {/* Mic */}
        <div style={{ position: 'absolute', right: 22, top: 26 }}>
          <SamsungCircleButton size={36}>
            <IconMic size={16} stroke={1.8} />
          </SamsungCircleButton>
        </div>

        {/* Row 2: Settings/Keypad (123) — directly under power */}
        <div style={{ position: 'absolute', left: 22, top: 70 }}>
          <SamsungCircleButton size={36}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0, lineHeight: 1 }}>
              <IconSettings size={11} stroke={1.8} />
              <div style={{ fontSize: 7, fontWeight: 700, letterSpacing: 0.4, marginTop: 1 }}>123</div>
            </div>
          </SamsungCircleButton>
        </div>

        {/* D-PAD — large circular nav (centered) */}
        <div style={{ position: 'absolute', top: 130, left: '50%', transform: 'translateX(-50%)' }}>
          <SamsungDPad outerSize={150} innerSize={62} />
        </div>

        {/* Row 4: Back / Home / Play-Pause */}
        {/* Back */}
        <div style={{ position: 'absolute', left: 28, top: 312 }}>
          <SamsungCircleButton size={34}>
            <IconBack size={15} stroke={2} />
          </SamsungCircleButton>
        </div>
        {/* Home (center) */}
        <div style={{ position: 'absolute', top: 308, left: '50%', transform: 'translateX(-50%)' }}>
          <SamsungCircleButton size={42}>
            <IconHome size={17} stroke={2} />
          </SamsungCircleButton>
        </div>
        {/* Play/Pause */}
        <div style={{ position: 'absolute', right: 28, top: 312 }}>
          <SamsungCircleButton size={34}>
            <IconPlayPause size={15} />
          </SamsungCircleButton>
        </div>

        {/* Row 5: Vol rocker (left) + Channel rocker (right) */}
        <div style={{ position: 'absolute', left: 22, top: 372 }}>
          <SamsungRocker
            width={72} height={32}
            top={<IconMinus size={13} stroke={2.2} />}
            bottom={<IconPlus size={13} stroke={2.2} />}
          />
        </div>
        <div style={{ position: 'absolute', right: 22, top: 372 }}>
          <SamsungRocker
            width={72} height={32}
            top={<IconChevronUp size={13} stroke={2.2} />}
            bottom={<IconChevronDown size={13} stroke={2.2} />}
          />
        </div>

        {/* CC/Mute label under volume rocker */}
        <div style={{
          position: 'absolute', left: 22, top: 410, width: 72,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
          fontSize: 8, fontWeight: 700, letterSpacing: 0.6, color: '#7a7a7e',
        }}>
          <span>CC/AD</span>
          <IconMute size={11} stroke={1.6} />
        </div>

        {/* Row 6: Streaming app slots — placeholders (no branding) */}
        {/* Top-left slot */}
        <div style={{ position: 'absolute', left: 22, top: 450 }}>
          <SamsungSlot size={42} label="APP" sublabel="1" />
        </div>
        {/* Top-right slot */}
        <div style={{ position: 'absolute', right: 22, top: 450 }}>
          <SamsungSlot size={42} label="APP" sublabel="2" />
        </div>
        {/* Center top slot */}
        <div style={{ position: 'absolute', top: 446, left: '50%', transform: 'translateX(-50%)' }}>
          <SamsungSlot size={50} label="LIVE" sublabel="TV" accent={accentRed} />
        </div>
        {/* Bottom-center slot */}
        <div style={{ position: 'absolute', top: 510, left: '50%', transform: 'translateX(-50%)' }}>
          <SamsungSlot size={50} label="APP" sublabel="3" />
        </div>
        {/* Bottom-right slot (paired) */}
        <div style={{ position: 'absolute', top: 514, right: 22 }}>
          <SamsungSlot size={42} label="APP" sublabel="4" />
        </div>

        {/* Brand label at bottom */}
        <div style={{
          position: 'absolute', bottom: 28, left: 0, right: 0,
          textAlign: 'center', fontSize: 11, fontWeight: 700, letterSpacing: 2,
          color: '#5a5a5e',
        }}>ANOTHER REMOTE</div>
      </div>

      {/* Home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.5)', zIndex: 30,
      }} />
    </div>
  );
}

window.RemoteSamsungStyle = RemoteSamsungStyle;
