/**
 * Generate Discord Server Logo for FS25 Modding Community
 * Design by Samantha, code by Claude
 *
 * Concept: Gear/cog with wheat stalk growing through center
 * Colors: GIANTS orange (#E87A1E) + Discord dark (#2C2F33) + wheat gold
 *
 * v2: Scaled up for Discord readability — bigger gear, bigger text,
 *     square background (Discord applies its own rounding)
 */

const fs = require('fs');
const path = require('path');

// Check for sharp
let sharp;
try {
    sharp = require('sharp');
} catch (e) {
    console.error('sharp not installed. Run: npm install sharp');
    process.exit(1);
}

const OUTPUT_DIR = path.join(__dirname, '..');
const SIZE = 512;

// Colors
const BG_COLOR = '#2C2F33';       // Discord dark theme
const BG_LIGHT = '#363A3F';       // Gradient center
const GEAR_COLOR = '#E87A1E';     // GIANTS orange
const GEAR_DARK = '#C4680F';      // Darker orange for depth
const WHEAT_COLOR = '#F0C040';    // Golden wheat
const WHEAT_DARK = '#D4A830';     // Wheat shadow
const ACCENT_GREEN = '#5B8C3E';   // Stem green
const TEXT_COLOR = '#FFFFFF';     // White text

function generateGearTeeth(numTeeth, innerR, outerR, toothWidth) {
    let paths = '';
    for (let i = 0; i < numTeeth; i++) {
        const angle = (i * 360 / numTeeth) * Math.PI / 180;
        const halfTooth = (toothWidth / 2) * Math.PI / 180;

        const x1 = Math.cos(angle - halfTooth) * innerR;
        const y1 = Math.sin(angle - halfTooth) * innerR;
        const x2 = Math.cos(angle - halfTooth * 0.7) * outerR;
        const y2 = Math.sin(angle - halfTooth * 0.7) * outerR;
        const x3 = Math.cos(angle + halfTooth * 0.7) * outerR;
        const y3 = Math.sin(angle + halfTooth * 0.7) * outerR;
        const x4 = Math.cos(angle + halfTooth) * innerR;
        const y4 = Math.sin(angle + halfTooth) * innerR;

        paths += `    <polygon points="${x1.toFixed(1)},${y1.toFixed(1)} ${x2.toFixed(1)},${y2.toFixed(1)} ${x3.toFixed(1)},${y3.toFixed(1)} ${x4.toFixed(1)},${y4.toFixed(1)}" fill="url(#gearGrad)"/>\n`;
    }
    return paths;
}

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 512 512">
  <defs>
    <!-- Background gradient -->
    <radialGradient id="bgGrad" cx="50%" cy="40%" r="60%">
      <stop offset="0%" stop-color="${BG_LIGHT}"/>
      <stop offset="100%" stop-color="${BG_COLOR}"/>
    </radialGradient>

    <!-- Gear gradient -->
    <linearGradient id="gearGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="${GEAR_COLOR}"/>
      <stop offset="100%" stop-color="${GEAR_DARK}"/>
    </linearGradient>

    <!-- Subtle outer glow -->
    <filter id="glow">
      <feGaussianBlur stdDeviation="4" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>
  </defs>

  <!-- Square background (Discord applies its own rounding) -->
  <rect x="0" y="0" width="512" height="512" fill="url(#bgGrad)"/>

  <!-- ===== GEAR (big, centered in upper portion) ===== -->
  <g transform="translate(256, 210)" filter="url(#glow)">
    <!-- Gear teeth (10 chunky teeth — fewer but bigger for readability) -->
    ${generateGearTeeth(10, 155, 185, 22)}

    <!-- Gear body -->
    <circle cx="0" cy="0" r="155" fill="url(#gearGrad)"/>

    <!-- Inner ring detail (thicker) -->
    <circle cx="0" cy="0" r="125" fill="none" stroke="${GEAR_DARK}" stroke-width="3.5" opacity="0.6"/>

    <!-- Center hole -->
    <circle cx="0" cy="0" r="62" fill="${BG_COLOR}"/>
    <circle cx="0" cy="0" r="62" fill="none" stroke="${GEAR_DARK}" stroke-width="3"/>

    <!-- ===== WHEAT STALK (thicc and proud) ===== -->
    <!-- Main stem -->
    <line x1="0" y1="58" x2="0" y2="-130" stroke="${ACCENT_GREEN}" stroke-width="10" stroke-linecap="round"/>

    <!-- Wheat head (top grain cluster — big fat grains) -->
    <!-- Central grains -->
    <ellipse cx="0" cy="-132" rx="12" ry="22" fill="${WHEAT_COLOR}"/>
    <ellipse cx="0" cy="-162" rx="11" ry="20" fill="${WHEAT_COLOR}"/>
    <ellipse cx="0" cy="-188" rx="9" ry="17" fill="${WHEAT_COLOR}"/>
    <ellipse cx="0" cy="-208" rx="7" ry="13" fill="${WHEAT_DARK}"/>

    <!-- Left grains -->
    <ellipse cx="-18" cy="-125" rx="11" ry="20" fill="${WHEAT_COLOR}" transform="rotate(-15, -18, -125)"/>
    <ellipse cx="-23" cy="-150" rx="9" ry="17" fill="${WHEAT_COLOR}" transform="rotate(-20, -23, -150)"/>
    <ellipse cx="-20" cy="-174" rx="8" ry="15" fill="${WHEAT_DARK}" transform="rotate(-18, -20, -174)"/>

    <!-- Right grains -->
    <ellipse cx="18" cy="-125" rx="11" ry="20" fill="${WHEAT_COLOR}" transform="rotate(15, 18, -125)"/>
    <ellipse cx="23" cy="-150" rx="9" ry="17" fill="${WHEAT_COLOR}" transform="rotate(20, 23, -150)"/>
    <ellipse cx="20" cy="-174" rx="8" ry="15" fill="${WHEAT_DARK}" transform="rotate(18, 20, -174)"/>

    <!-- Awns (whiskers at top — bold) -->
    <line x1="0" y1="-208" x2="-16" y2="-236" stroke="${WHEAT_DARK}" stroke-width="4" stroke-linecap="round"/>
    <line x1="0" y1="-208" x2="16" y2="-236" stroke="${WHEAT_DARK}" stroke-width="4" stroke-linecap="round"/>
    <line x1="0" y1="-208" x2="0" y2="-244" stroke="${WHEAT_COLOR}" stroke-width="4" stroke-linecap="round"/>

    <!-- Leaves on stem (bold sweeping curves) -->
    <path d="M 0,-40 Q 34,-60 20,-92" fill="none" stroke="${ACCENT_GREEN}" stroke-width="6" stroke-linecap="round"/>
    <path d="M 0,-12 Q -32,-34 -18,-62" fill="none" stroke="${ACCENT_GREEN}" stroke-width="6" stroke-linecap="round"/>
  </g>

  <!-- ===== TEXT: "FS25" (on the lower gear — dark outline for contrast on orange) ===== -->
  <text x="256" y="330" text-anchor="middle" font-family="Arial Black, Arial, sans-serif" font-weight="900" font-size="110" fill="${TEXT_COLOR}" letter-spacing="10" stroke="${BG_COLOR}" stroke-width="6" paint-order="stroke">FS25</text>

  <!-- ===== RIBBON BANNER with "MODDING" (HUGE — owns the bottom) ===== -->
  <g transform="translate(256, 430)">
    <!-- Ribbon tails (darker orange, V-notch cut) -->
    <polygon points="-248,-40 -214,-40 -214,40 -248,40 -228,0" fill="${GEAR_DARK}"/>
    <polygon points="248,-40 214,-40 214,40 248,40 228,0" fill="${GEAR_DARK}"/>
    <!-- Ribbon center band (80px tall!) -->
    <rect x="-214" y="-40" width="428" height="80" rx="3" fill="${GEAR_COLOR}"/>
    <!-- Ribbon fold shadows -->
    <line x1="-214" y1="-40" x2="-214" y2="40" stroke="${GEAR_DARK}" stroke-width="2.5"/>
    <line x1="214" y1="-40" x2="214" y2="40" stroke="${GEAR_DARK}" stroke-width="2.5"/>
    <!-- MODDING text (white on orange, massive) -->
    <text x="0" y="24" text-anchor="middle" font-family="Arial Black, Arial, sans-serif" font-weight="900" font-size="70" fill="${TEXT_COLOR}" letter-spacing="8" stroke="${BG_COLOR}" stroke-width="3" paint-order="stroke">MODDING</text>
  </g>
</svg>`;

async function generate() {
    console.log('Generating Discord logo v2 (scaled up for readability)...');

    // Write SVG
    const svgPath = path.join(OUTPUT_DIR, 'discord_logo.svg');
    fs.writeFileSync(svgPath, svg);
    console.log(`  SVG: ${svgPath}`);

    // Generate PNG at 512px (high-res for Discord)
    const pngPath = path.join(OUTPUT_DIR, 'discord_logo.png');
    await sharp(Buffer.from(svg))
        .resize(512, 512)
        .png()
        .toFile(pngPath);
    console.log(`  PNG (512px): ${pngPath}`);

    // Generate Discord avatar size (128px) for preview
    const avatarPath = path.join(OUTPUT_DIR, 'discord_logo_128.png');
    await sharp(Buffer.from(svg))
        .resize(128, 128)
        .png()
        .toFile(avatarPath);
    console.log(`  PNG (128px): ${avatarPath}`);

    console.log('\nDone! Use discord_logo.png for your Discord server icon.');
}

generate().catch(err => {
    console.error('Error:', err);
    process.exit(1);
});
