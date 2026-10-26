# React Bits 컴포넌트 목록

생성: 2026-10-26 · 출처 https://reactbits.dev/llms.txt + https://reactbits.dev/r/registry.json · 컴포넌트 218개

의존성은 TS-TW 변형 기준 요약이다. 실제 설치 의존성은 받을 때 registry JSON 의 `dependencies` 를 따른다.
변형이 4개(JS-CSS, JS-TW, TS-CSS, TS-TW) 다 있지 않은 것만 "변형" 칸에 적는다.

## Animations (38)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| [AnimatedContent](https://www.reactbits.dev/animations/animated-content) | Wrapper that reveals its content on scroll with slides, blur, 3D tilts, soft wipes and staggered children. | gsap@^3.13.0 |  |
| [BlobCursor](https://www.reactbits.dev/animations/blob-cursor) | Liquid metal blob cursor that stretches, sloshes and bursts into droplets, in chrome, jelly, pearl or ink. | three@^0.180.0 |  |
| [ClickSpark](https://www.reactbits.dev/animations/click-spark) | Bursts of sparks at every click, as dashes, comets, dots or stars, that can spill around buttons. | - |  |
| [Crosshair](https://www.reactbits.dev/animations/crosshair) | Crosshair cursor with live coordinates that locks onto links and buttons and measures them. | - |  |
| [CrystalizedBall](https://www.reactbits.dev/animations/crystalized-ball) | A glass ball with a crackling electric rim and glowing dust that swirls with the cursor. | ogl@^1.0.11 |  |
| [Cubes](https://www.reactbits.dev/animations/cubes) | A grid of outlined 3D cubes that turn to face the cursor, spin when swept and ripple on click. | - |  |
| [CursorGrid](https://www.reactbits.dev/animations/cursor-grid) | A crisp grid whose cells light up and fade behind the cursor, with grid styles, tiles and click pulses. | - |  |
| [DitherVeil](https://www.reactbits.dev/animations/dither-veil) | A 1-bit dithered photo the cursor burns through to full colour, knitting back cell by cell. | ogl@^1.0.11 |  |
| [ElasticMesh](https://www.reactbits.dev/animations/elastic-mesh) | Turns text or any logo into a puffy inflated shape you can press, poke and stretch like jelly. | - |  |
| [ElectricBorder](https://www.reactbits.dev/animations/electric-border) | Wraps any element in crackling strands of current that surge near the cursor and leap off in sparks. | - |  |
| [ElectricLogo](https://www.reactbits.dev/animations/electric-logo) | Turns any logo into a living lightning outline, with arcs that leap off its edges. | ogl@^1.0.11 |  |
| [FadeContent](https://www.reactbits.dev/animations/fade-content) | Wrapper that fades content in on scroll, plain or out of focus, from washed-out gray, or through grain, mist and pixel blocks. | gsap@^3.13.0 |  |
| [GhostCursor](https://www.reactbits.dev/animations/ghost-cursor) | A ghost of glowing smoke that floats after the cursor and curls away as it rises. | - |  |
| [GlareHover](https://www.reactbits.dev/animations/glare-hover) | A glossy light streak that sweeps across any element in the direction the cursor moves. | - |  |
| [GlowCursor](https://www.reactbits.dev/animations/glow-cursor) | Light that pours from the cursor, drifts softly through the air and cools as it fades. | - |  |
| [GradualBlur](https://www.reactbits.dev/animations/gradual-blur) | Progressive edge blur for headers, footers, captions and carousels, with an optional fade to color that hides at the ends of a scroll. | - |  |
| [HalftoneReveal](https://www.reactbits.dev/animations/halftone-reveal) | A halftone print of an image whose dots swell into the real photo under the cursor. | - |  |
| [ImageTrail](https://www.reactbits.dev/animations/image-trail) | Cursor-based image trail with several built-in variants. | gsap@^3.13.0 |  |
| [LaserFlow](https://www.reactbits.dev/animations/laser-flow) | A beam of light that splashes onto your content and pours over its corners. | - |  |
| [LogoLoop](https://www.reactbits.dev/animations/logo-loop) | Continuously looping marquee of brand or tech logos with seamless repeat and hover pause. | - |  |
| [Magnet](https://www.reactbits.dev/animations/magnet) | Elements magnetically ease toward the cursor then settle back with spring physics. | - |  |
| [MetaBalls](https://www.reactbits.dev/animations/meta-balls) | Liquid metaballs that merge, stretch and pinch apart, with a cursor blob that pushes through them. | - |  |
| [MetallicPaint](https://www.reactbits.dev/animations/metallic-paint) | Liquid chrome that flows over your logo or text, adapted from Paper's Liquid Metal shader. | - |  |
| [Noise](https://www.reactbits.dev/animations/noise) | Film grain overlay for photos and pages, from fine 35mm grain to dust, paper and TV static. | - |  |
| [OrbitImages](https://www.reactbits.dev/animations/orbit-images) | SVG Path customizable orbiting images effect. | - |  |
| [PixelSwap](https://www.reactbits.dev/animations/pixel-swap) | New content builds in pixel by pixel in a springy wave that starts wherever the cursor enters. | - |  |
| [PixelTrail](https://www.reactbits.dev/animations/pixel-trail) | Glossy pixels melt into a fluid goo trail behind the cursor, with color shifts and drips. | - |  |
| [PixelTransition](https://www.reactbits.dev/animations/pixel-transition) | Retro pixel dissolve that covers a card in solid pixels, swaps the content underneath and clears again. | - |  |
| [Ribbons](https://www.reactbits.dev/animations/ribbons) | Springy ribbons that trail the cursor, in lens, comet or even shapes with an optional wave. | - |  |
| [RippleDistortion](https://www.reactbits.dev/animations/ripple-distortion) | Pointer-driven water displacement that warps content and leaves a decaying wake. | ogl@^1.0.11 |  |
| [ScrollExpand](https://www.reactbits.dev/animations/scroll-expand) | A rounded media frame that grows to full bleed as it scrolls through the viewport. | - |  |
| [ShapeBlur](https://www.reactbits.dev/animations/shape-blur) | A crisp logo or shape that drifts out of focus under the pointer like a camera lens. | - |  |
| [SplashCursor](https://www.reactbits.dev/animations/splash-cursor) | A fluid simulation that trails the cursor in swirling ink and bursts into a splash on click. | - |  |
| [StarBorder](https://www.reactbits.dev/animations/star-border) | A twinkling star that travels the exact outline of any button, pill or card, trailing light and stardust. | - |  |
| [StickerPeel](https://www.reactbits.dev/animations/sticker-peel) | A die-cut sticker you can peel at any edge, drag, throw and swing, in gloss, matte or holographic finishes. | - |  |
| [Strands](https://www.reactbits.dev/animations/strands) | Spectral strands that twist inside a frosted glass orb and swell into a smooth bulge where they come together, like the new Siri. | - |  |
| [SwarmCursor](https://www.reactbits.dev/animations/swarm-cursor) | A liquid swarm of particles that flows after the cursor, curls into eddies and pours around hovered buttons. | - |  |
| [TargetCursor](https://www.reactbits.dev/animations/target-cursor) | A reticle cursor whose corner brackets snap around targets, matching their shape. | react-dom@^19.0.0 |  |

## Backgrounds (63)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| [AcidSquares](https://www.reactbits.dev/backgrounds/acid-squares) | A rolling field of glossy squares that ripples under two drifting colored lights. | - |  |
| [AeroShards](https://www.reactbits.dev/backgrounds/aero-shards) | Silk ribbons of thick glass shards streaming on layered depths among survey markers, catching light along their edges. | vgpu@^0.3.1 |  |
| [Antigravity](https://www.reactbits.dev/backgrounds/antigravity) | A field of particles that lifts into a glowing ring around the cursor and bursts outward on click. | - |  |
| [Aurora](https://www.reactbits.dev/backgrounds/aurora) | A soft, calm aurora that flows across the top of the page and drifts toward the cursor. | - |  |
| [Balatro](https://www.reactbits.dev/backgrounds/balatro) | The swirling Balatro paint shader, with crisp pixels, a cursor that stirs the paint and click whirlpools. | - |  |
| [Ballpit](https://www.reactbits.dev/backgrounds/ballpit) | A soft-lit pit of physics balls you can shove with the cursor, grab, throw and blast apart. | - |  |
| [Beams](https://www.reactbits.dev/backgrounds/beams) | Glossy ribbons that ripple in the dark and catch the light, which follows your cursor. | - |  |
| [ColorBends](https://www.reactbits.dev/backgrounds/color-bends) | Vibrant color bends with smooth flowing animation. | three@^0.180.0 |  |
| [CRTWarp](https://www.reactbits.dev/backgrounds/crt-warp) | A blocky plasma glowing on a curved CRT, with real scanlines, a phosphor mask, afterglow and a power-on intro. | - |  |
| [DarkVeil](https://www.reactbits.dev/backgrounds/dark-veil) | A silky veil of light that drifts in the dark and bends around the cursor. | - |  |
| [Dither](https://www.reactbits.dev/backgrounds/dither) | Retro dithered waves with Bayer, halftone, line and noise patterns, palettes and cursor trails. | - |  |
| [DotField](https://www.reactbits.dev/backgrounds/dot-field) | A gradient dot field seen through a lens that follows the cursor, magnifying, pinching or swirling the dots. | - |  |
| [DotGrid](https://www.reactbits.dev/backgrounds/dot-grid) | A springy dot grid that the cursor flicks and drags through like jelly, with click shockwaves. | - |  |
| [FaultyTerminal](https://www.reactbits.dev/backgrounds/faulty-terminal) | A flickering CRT terminal of glowing glyphs, with phosphor trails under the cursor and glitches on click. | - |  |
| [Ferrofluid](https://www.reactbits.dev/backgrounds/ferrofluid) | A glossy sea of magnetic fluid where swells of spikes roll in and the cursor raises a crown. | - |  |
| [FloatingLines](https://www.reactbits.dev/backgrounds/floating-lines) | Ribbons of fine glowing lines that drift in waves, part around the cursor and curl when clicked. | - |  |
| [FluxLines](https://www.reactbits.dev/backgrounds/flux-lines) | Glowing flux lines tracing a churning magnetic fluid. The cursor magnet reveals and curls them. | - |  |
| [Galaxy](https://www.reactbits.dev/backgrounds/galaxy) | Endless flight through a twinkling starfield with warp jumps, cursor repulsion and star palettes. | - |  |
| [GhostFibers](https://www.reactbits.dev/backgrounds/ghost-fibers) | Layered ribbons of fine glowing fibers that twist, fold and drift through soft depth of field. | - |  |
| [GradientASCII](https://www.reactbits.dev/backgrounds/gradient-ascii) | Soft gradient glows drawn in ASCII characters that scramble under the cursor. | - |  |
| [GradientBlinds](https://www.reactbits.dev/backgrounds/gradient-blinds) | Satin gradient blinds lit by a spotlight that follows the cursor, swaying and turning toward the light. | - |  |
| [GradientWaves](https://www.reactbits.dev/backgrounds/gradient-waves) | Lit satin waves rolling in from a hazy horizon, with a light that follows the cursor and swells on click. | - |  |
| [Grainient](https://www.reactbits.dev/backgrounds/grainient) | Flowing grainy gradients you can stir with the cursor. | - |  |
| [GridDistortion](https://www.reactbits.dev/backgrounds/grid-distortion) | Image background that breaks into a grid of blocks under the cursor and settles back into place. | - |  |
| [GridMotion](https://www.reactbits.dev/backgrounds/grid-motion) | A tilted wall of drifting tiles that slides with the pointer and lights up where it rests. | - |  |
| [GridScan](https://www.reactbits.dev/backgrounds/grid-scan) | A 3D grid room swept by a scanning light that follows your view. | - |  |
| [Hyperspeed](https://www.reactbits.dev/backgrounds/hyperspeed) | Night highway of glowing light trails on a winding road that warps into hyperspace while you hold. | three@^0.180.0 |  |
| [Iridescence](https://www.reactbits.dev/backgrounds/iridescence) | Liquid iridescent surface with shifting folds that you can stir with the cursor. | - |  |
| [LetterGlitch](https://www.reactbits.dev/backgrounds/letter-glitch) | A calm field of letters that flicker, scramble and glitch in color, stirred by the cursor and torn by clicks. | - |  |
| [Lightfall](https://www.reactbits.dev/backgrounds/lightfall) | Streaks of light falling down a curved tunnel, bending around the cursor and stretching into warp trails on hold. | - |  |
| [Lightning](https://www.reactbits.dev/backgrounds/lightning) | Crackling, branching lightning that bends toward the cursor and strikes wherever you click. | - |  |
| [LightPillar](https://www.reactbits.dev/backgrounds/light-pillar) | A swirling pillar of light that ignites on load, leans toward the cursor and surges on click. | - |  |
| [LightRays](https://www.reactbits.dev/backgrounds/light-rays) | Volumetric light rays from any edge, with source glow and haze. The cursor steers the beam and casts a shadow. | - |  |
| [LightTunnel](https://www.reactbits.dev/backgrounds/light-tunnel) | A swirling fibre-optic tunnel where comets of light race into depth, steered by the cursor. | - |  |
| [LineWaves](https://www.reactbits.dev/backgrounds/line-waves) | Fine lines that flow in silky waves while a band of light drifts through them. | - |  |
| [LiquidChrome](https://www.reactbits.dev/backgrounds/liquid-chrome) | Soft ribbons of liquid chrome that swirl through a dark pool, ripple under the cursor and catch the light as it moves. | - |  |
| [LiquidEther](https://www.reactbits.dev/backgrounds/liquid-ether) | A glowing liquid that swirls under the cursor, colored by how fast it flows. | - |  |
| [MagicRings](https://www.reactbits.dev/backgrounds/magic-rings) | Glowing rings that pulse outward in a wave, swell toward the cursor and flare on click. | - |  |
| [MagnetLines](https://www.reactbits.dev/backgrounds/magnet-lines) | A field of magnetic lines that swing toward the cursor, ripple outward and spin with every click. | - |  |
| [MicroSlats](https://www.reactbits.dev/backgrounds/micro-slats) | A wall of tiny slats that becomes a rolling sea in perspective, with glinting crests. | ogl@^1.0.11 |  |
| [MoltenMetal](https://www.reactbits.dev/backgrounds/molten-metal) | Swirling caustic filaments with white-hot cores that heat up under the cursor and flare on click. | - |  |
| [Orb](https://www.reactbits.dev/backgrounds/orb) | A glowing ring of swirling color that breathes, trails an orbiting light and reaches toward the cursor. | - |  |
| [Particles](https://www.reactbits.dev/backgrounds/particles) | A drifting 3D field of particles with glow, twinkle, constellation lines and cursor interaction. | - |  |
| [PatternWaves](https://www.reactbits.dev/backgrounds/pattern-waves) | A lit halftone surface of dots, lines or glyphs that moves like draped silk. | ogl@^1.0.11 |  |
| [PixelBlast](https://www.reactbits.dev/backgrounds/pixel-blast) | Dithered pixel clouds that drift, shimmer and light up under the cursor, with ripples, shapes and a perspective floor. | - |  |
| [PixelSnow](https://www.reactbits.dev/backgrounds/pixel-snow) | Pixel-art snowflakes drifting down in layers of depth, brushed aside by the cursor. | - |  |
| [Plasma](https://www.reactbits.dev/backgrounds/plasma) | Folds of satin light twisting slowly through the dark, turning to follow the cursor. | - |  |
| [PlasmaWave](https://www.reactbits.dev/backgrounds/plasma-wave) | Two ribbons of plasma curling through each other, with soft glow and white-hot cores. | - |  |
| [Prism](https://www.reactbits.dev/backgrounds/prism) | Rotating prism of glowing spectral light with configurable shape, colors and motion. | - |  |
| [PrismaticBurst](https://www.reactbits.dev/backgrounds/prismatic-burst) | A burst of prismatic light rays that leans toward the cursor and sends a wave of light outward on click. | - |  |
| [Radar](https://www.reactbits.dev/backgrounds/radar) | A radar scope whose sweep leaves a phosphor afterglow and picks up moving contacts. | - |  |
| [RippleGrid](https://www.reactbits.dev/backgrounds/ripple-grid) | A crisp grid that ripples like water, bending and lighting up as waves pass through it. | - |  |
| [Scanner](https://www.reactbits.dev/backgrounds/scanner) | Glowing interference lines swept by a scan beam, with a CRT finish, cursor lensing and click pings. | - |  |
| [ShapeGrid](https://www.reactbits.dev/backgrounds/shape-grid) | A drifting grid of shapes that lights up under the cursor, with perspective tilt and rainbow trails. | - |  |
| [ShapeWaves](https://www.reactbits.dev/backgrounds/shape-waves) | A field of triangles, circles and squares that brighten and grow along rolling waves. | vgpu@^0.3.1 |  |
| [SideRays](https://www.reactbits.dev/backgrounds/side-rays) | Shafts of light that fan in from a corner or side, shimmer slowly and lean toward the cursor. | - |  |
| [Silk](https://www.reactbits.dev/backgrounds/silk) | Flowing satin folds with glossy highlights that turn toward the cursor and ripple on click. | - |  |
| [SlicedWaves](https://www.reactbits.dev/backgrounds/sliced-waves) | Waves of colored light sliced into glowing bars, seen in depth with a focus that follows the cursor. | - |  |
| [SoftAurora](https://www.reactbits.dev/backgrounds/soft-aurora) | Soft aurora borealis shader with 3D Perlin noise and cosine gradient palettes. | - |  |
| [Threads](https://www.reactbits.dev/backgrounds/threads) | Flowing threads that fray apart and part around the cursor, from fine silk to contour lines. | - |  |
| [Topography](https://www.reactbits.dev/backgrounds/topography) | A 3D landscape drawn in glowing contour lines that rises under the cursor, with light pulses on click. | - |  |
| [Waves](https://www.reactbits.dev/backgrounds/waves) | Dense flowing lines that sway like silk, bend around the cursor and spring back into place. | - |  |
| [WebThreads](https://www.reactbits.dev/backgrounds/web-threads) | Glowing threads woven through luminous pinch points that light up under the cursor and carry light on click. | - |  |

## Components (48)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| [AccordionGallery](https://www.reactbits.dev/components/accordion-gallery) | Panels expand on hover or focus, revealing parallax imagery and captions. | gsap@^3.13.0 |  |
| [AnimatedList](https://www.reactbits.dev/components/animated-list) | A scrolling list whose rows spring into view, with a gliding selection and arrow keys. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [BorderGlow](https://www.reactbits.dev/components/border-glow) | Glowing mesh-gradient border that follows cursor direction and intensifies near edges. | - |  |
| [BounceCards](https://www.reactbits.dev/components/bounce-cards) | A fan of photo cards that bounce in, then spread apart and straighten the one you hover. | - |  |
| [BubbleMenu](https://www.reactbits.dev/components/bubble-menu) | Floating circular expanding menu with staggered item reveal. | gsap@^3.13.0 |  |
| [CardNav](https://www.reactbits.dev/components/card-nav) | A navigation bar that springs open into a row of cards, each with its own links. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [CardSwap](https://www.reactbits.dev/components/card-swap) | A 3D stack of cards that sends the front card to the back on a timer, or when you fling it. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [Carousel](https://www.reactbits.dev/components/carousel) | Swipeable cards for feature tours, stories and galleries, with five transitions and an autoplay timer. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [ChromaGrid](https://www.reactbits.dev/components/chroma-grid) | A grid of grayscale photo cards where a spotlight follows the cursor and brings back color. | - |  |
| [CircularCarousel](https://www.reactbits.dev/components/circular-carousel) | A 3D ring of images with bendable cards, momentum drag, snapping and click to focus. | - |  |
| [CircularGallery](https://www.reactbits.dev/components/circular-gallery) | A curved image gallery you can drag, scroll or tab through, with cards that open to the full image. | - |  |
| [Counter](https://www.reactbits.dev/components/counter) | An odometer-style number whose digits roll to every new value, with currency, separators and locales. | - |  |
| [CurvedInput](https://www.reactbits.dev/components/curved-input) | Arc-bent input bar with text, caret and submit button all following the curve. | - |  |
| [DecayCard](https://www.reactbits.dev/components/decay-card) | An image card that tears and melts as the pointer moves, then pulls itself back together. | - |  |
| [DepthCarousel](https://www.reactbits.dev/components/depth-carousel) | Cards recede into depth on a 3D rail, with drag, keyboard and auto-advance. | gsap@^3.13.0 |  |
| [Dock](https://www.reactbits.dev/components/dock) | macOS style dock with smooth magnification, launch bounce, badges and context menus. | react-dom@^19.0.0 |  |
| [DomeGallery](https://www.reactbits.dev/components/dome-gallery) | Immersive 3D dome gallery projecting images on a hemispheric surface. | @use-gesture/react@^10.2.27 |  |
| [DriftWall](https://www.reactbits.dev/components/drift-wall) | An endless perspective wall of tiles drifting past, lifting on hover. | - |  |
| [ElasticSlider](https://www.reactbits.dev/components/elastic-slider) | A slider that grows under your cursor and stretches like rubber when pulled past either end, then springs back. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [FlexCarousel](https://www.reactbits.dev/components/flex-carousel) | An infinite image row that flows through invisible liquid glass at its edges. | ogl@^1.0.11 |  |
| [FlowingMenu](https://www.reactbits.dev/components/flowing-menu) | A full-height menu with a liquid band that glides between rows and reveals a scrolling marquee of each item. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [FluidGlass](https://www.reactbits.dev/components/fluid-glass) | A 3D glass object that refracts your headline, image or video, follows the cursor and melts between shapes. | - |  |
| [FlyingPosters](https://www.reactbits.dev/components/flying-posters) | 3D posters that twist and flip as you scroll or drag through an endless column. | - |  |
| [Folder](https://www.reactbits.dev/components/folder) | Folder that drops its flap open or swings open like a book, with pages you can pick. | - |  |
| [GlassIcons](https://www.reactbits.dev/components/glass-icons) | Liquid glass icons that bend the color behind them, for app grids, docks and social links. | - |  |
| [GlassSurface](https://www.reactbits.dev/components/glass-surface) | Apple-style liquid glass that bends what is behind it, in a rounded panel or any logo shape. | - |  |
| [GooeyNav](https://www.reactbits.dev/components/gooey-nav) | A navigation bar whose active pill breaks into goo that flows over to the item you pick. | - |  |
| [HoloCard](https://www.reactbits.dev/components/holo-card) | Collectible trading card with a real holographic foil and glitter that sparkles as it tilts. | - |  |
| [InfiniteMenu](https://www.reactbits.dev/components/infinite-menu) | A draggable sphere of image tiles that snaps the nearest one forward and shows its title. | - |  |
| [InfiniteSpiral](https://www.reactbits.dev/components/infinite-spiral) | An endlessly looping 3D helix of images with adjustable motion, depth and spacing. | - |  |
| [Lanyard](https://www.reactbits.dev/components/lanyard) | Swinging 3D badge on a stretchy woven band that you can drag, throw or click to flip. | three@^0.180.0 |  |
| [LineSidebar](https://www.reactbits.dev/components/line-sidebar) | Static list navigation with a cursor-proximity effect that shifts and highlights nearby items. | - |  |
| [MagicBento](https://www.reactbits.dev/components/magic-bento) | A bento grid of feature cards with live artwork, edge light that follows the cursor and a click wave. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [Masonry](https://www.reactbits.dev/components/masonry) | A masonry gallery that springs into place, reflows as it resizes and opens images in a lightbox. | react-dom@^19.0.0, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [ModelViewer](https://www.reactbits.dev/components/model-viewer) | A product-style 3D model viewer that frames itself and floats over a soft shadow. | @react-three/fiber@^9.3.0, @react-three/drei@^10.7.4, three@^0.180.0 |  |
| [MorphSlider](https://www.reactbits.dev/components/morph-slider) | WebGL slider that melts between images with a displacement transition. | ogl@^1.0.11, gsap@^3.13.0 |  |
| [OptionWheel](https://www.reactbits.dev/components/option-wheel) | Curved option picker that spins with scroll, drag or arrow keys, tilting items away. | - |  |
| [PillNav](https://www.reactbits.dev/components/pill-nav) | A pill navigation bar where a fill rises through each link as its label rolls over, with a sliding active dot. | - |  |
| [PixelCard](https://www.reactbits.dev/components/pixel-card) | A card that fills with twinkling pixels on hover, rippling out from the center or the cursor. | - |  |
| [ProfileCard](https://www.reactbits.dev/components/profile-card) | A framed profile card that tilts toward the cursor, with holographic foil shining through a tiled pattern. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [ReflectiveCard](https://www.reactbits.dev/components/reflective-card) | A metal ID card that reflects your camera or a looping video and catches the light as it tilts. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [ScrollStack](https://www.reactbits.dev/components/scroll-stack) | Cards pin and stack as you scroll, settling back into a dimmed deck with smooth, jitter-free motion. | - |  |
| [SpecularButton](https://www.reactbits.dev/components/specular-button) | Glass button whose edge catches the light, with a highlight that glides toward the cursor. | - |  |
| [SpotlightCard](https://www.reactbits.dev/components/spotlight-card) | Card lit by a soft spotlight that follows the pointer, catches its edge and reaches nearby cards. | - |  |
| [Stack](https://www.reactbits.dev/components/stack) | Pile of cards you can drag, flick or click through, with thrown cards tucking underneath. | motion@^12.23.12 |  |
| [StaggeredMenu](https://www.reactbits.dev/components/staggered-menu) | Menu with staggered item animations and smooth transitions on open/close. | gsap@^3.13.0 |  |
| [Stepper](https://www.reactbits.dev/components/stepper) | A multi-step flow with a gliding step indicator, spring transitions and horizontal or vertical layouts. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [TiltedCard](https://www.reactbits.dev/components/tilted-card) | A 3D card that tilts toward the cursor, with glare, a soft shadow, floating layers and a flip side. | - |  |

## Micro (35)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| [BellToggle](https://www.reactbits.dev/micro/bell-toggle) | Pill toggle where a press rings the bell, crossfades the label and unfurls the pill. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [BranchedMenu](https://www.reactbits.dev/micro/branched-menu) | Collapsible menu that branches each section from a trunk and traces a line to your pick. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [CallChip](https://www.reactbits.dev/micro/call-chip) | Tool-call chip whose fill wipes across as a live timer ticks, ending green or shaking red. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [CodeSlots](https://www.reactbits.dev/micro/code-slots) | One-time code input whose digits spring into their slots, with paste and SMS autofill. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [CometDial](https://www.reactbits.dev/micro/comet-dial) | Tick-ring dial you flick by angle, with a comet that streaks behind the lit head. | motion@^12.23.12 |  |
| [DodgeField](https://www.reactbits.dev/micro/dodge-field) | Wrapper that makes any child dodge the pointer until it relents and glides home. | motion@^12.23.12 |  |
| [FlipCard](https://www.reactbits.dev/micro/flip-card) | Two-faced card that flips in 3D on a click, drag or flick and settles on a spring. | motion@^12.23.12 |  |
| [FlyingButton](https://www.reactbits.dev/micro/flying-button) | Button that fires its thrusters on hover, lifts off on a WebGL smoke plume and lands back in its own cloud. | - |  |
| [FolderFloat](https://www.reactbits.dev/micro/folder-float) | Folder whose notes spring out into a floating cloud when it opens on hover or press. | matter-js@^0.20.0 |  |
| [FuseButton](https://www.reactbits.dev/micro/fuse-button) | Action button whose done state carries an undo on a burning fuse. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [GlideSelect](https://www.reactbits.dev/micro/glide-select) | Select chip whose menu pops from its corner and whose highlight glides between rows. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [HoldButton](https://www.reactbits.dev/micro/hold-button) | Hold-to-confirm button whose liquid fill rises while pressed and snaps back if you let go. | - |  |
| [JellyRadio](https://www.reactbits.dev/micro/jelly-radio) | Radio group of chips where the chosen one swells and barges its neighbours outward. | motion@^12.23.12 |  |
| [LatticeLoader](https://www.reactbits.dev/micro/lattice-loader) | Agent status row with a lattice of cells that brighten in a wave beside a live stopwatch. | - |  |
| [PaperCrumple](https://www.reactbits.dev/micro/paper-crumple) | An image that crumples into a textured 3D sheet while you hold and drag it. | three@^0.180.0 |  |
| [PeekRating](https://www.reactbits.dev/micro/peek-rating) | Star rating that lifts a wave of stars up to the pointer, then commits with a pop on click. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [PromptBar](https://www.reactbits.dev/micro/prompt-bar) | Chat composer with @ sources, / commands, a model picker, dictation and attachments. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [PulseHeart](https://www.reactbits.dev/micro/pulse-heart) | Like button that contracts to a dot, flips colour and pulses back as the count ticks over. | @hugeicons/core-free-icons@^4.3.3 |  |
| [RefineFrame](https://www.reactbits.dev/micro/refine-frame) | Media frame that steps an image through generation stages without any layout shift. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [RubberSegment](https://www.reactbits.dev/micro/rubber-segment) | Segmented control whose rubber thumb stretches across the gap and squashes into place. | motion@^12.23.12 |  |
| [ScrubField](https://www.reactbits.dev/micro/scrub-field) | Number chip you drag to scrub, with rubber-band limits and click to type. | motion@^12.23.12 |  |
| [Shredder](https://www.reactbits.dev/micro/shredder) | A list with a paper shredder at the bottom that cuts dragged rows into curling strips. | react-dom@^19.0.0 |  |
| [SlideCommit](https://www.reactbits.dev/micro/slide-commit) | Slide-to-confirm handle that spins while your action runs and unfurls into a done pill. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [SlingButton](https://www.reactbits.dev/micro/sling-button) | Send button you pull back like a slingshot and release to fire. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [SloshGauge](https://www.reactbits.dev/micro/slosh-gauge) | Tank gauge whose liquid chases the value, tilts as it moves and splashes when it fills. | - |  |
| [SpringCheck](https://www.reactbits.dev/micro/spring-check) | Checkbox row where one spring fills the box, draws the tick and strikes through the label. | motion@^12.23.12, @hugeicons/core-free-icons@^4.3.3 |  |
| [SquishSwitch](https://www.reactbits.dev/micro/squish-switch) | Switch whose thumb stretches with speed and squashes against the end when you flick it. | motion@^12.23.12 |  |
| [StatusMark](https://www.reactbits.dev/micro/status-mark) | Agent task status glyph that morphs from an idle ring to a progress arc, then a check. | motion@^12.23.12 |  |
| [SwipeRow](https://www.reactbits.dev/micro/swipe-row) | List row that swipes open to reveal actions and deletes on a full swipe. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [SwipeToast](https://www.reactbits.dev/micro/swipe-toast) | Toast that swipes down to dismiss and burns a thin fuse for its remaining time. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [TearTicket](https://www.reactbits.dev/micro/tear-ticket) | Ticket whose perforated stub tears off by hand, fibre by fibre, and drops away. | motion@^12.23.12 |  |
| [ThoughtLine](https://www.reactbits.dev/micro/thought-line) | Reasoning trace header with a live clock that folds its steps into one line when done. | motion@^12.23.12, @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [VoicePill](https://www.reactbits.dev/micro/voice-pill) | Mic button that swells into a capsule of live equalizer bars and a timer while recording. | @hugeicons/react@^1.1.10, @hugeicons/core-free-icons@^4.3.3 |  |
| [WakeSlider](https://www.reactbits.dev/micro/wake-slider) | Thumbless range slider of thin bars where drag speed raises a wake behind the handle. | motion@^12.23.12 |  |
| [WarmTooltip](https://www.reactbits.dev/micro/warm-tooltip) | Tooltip group where the first label waits, then its siblings open instantly while warm. | react-dom@^19.0.0, motion@^12.23.12 |  |

## Text Animations (33)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| [ASCIIText](https://www.reactbits.dev/text-animations/ascii-text) | Waving ASCII text that tilts toward the pointer, scrambles on hover and ripples on click. | - |  |
| [BlurText](https://www.reactbits.dev/text-animations/blur-text) | Text starts blurred then crisply resolves for a soft-focus reveal effect. | motion@^12.23.12 |  |
| [CircularText](https://www.reactbits.dev/text-animations/circular-text) | Layouts characters around a circle with optional rotation animation. | motion@^12.23.12 |  |
| [CountUp](https://www.reactbits.dev/text-animations/count-up) | Animated number counter supporting formatting and decimals. | motion@^12.23.12 |  |
| [CurvedLoop](https://www.reactbits.dev/text-animations/curved-loop) | Flowing looping text path along a customizable curve with drag interaction. | - |  |
| [DecryptedText](https://www.reactbits.dev/text-animations/decrypted-text) | Hacker-style decryption cycling random glyphs until resolving to real text. | motion@^12.23.12 |  |
| [DepthText](https://www.reactbits.dev/text-animations/depth-text) | Layered extruded type with parallax that shifts against the pointer. | - |  |
| [EchoText](https://www.reactbits.dev/text-animations/echo-text) | Ghosted copies trail behind the text and settle into a single word. | - |  |
| [FallingText](https://www.reactbits.dev/text-animations/falling-text) | Text that breaks apart and tumbles into a pile you can drag, throw and swipe, then flies back into place. | matter-js@^0.20.0 |  |
| [FoldText](https://www.reactbits.dev/text-animations/fold-text) | Lines unfold into place like creased paper opening flat. | gsap@^3.13.0 |  |
| [FuzzyText](https://www.reactbits.dev/text-animations/fuzzy-text) | Vibrating fuzzy text with controllable hover intensity. | - |  |
| [GlitchText](https://www.reactbits.dev/text-animations/glitch-text) | RGB split and distortion glitch effect with jitter effects. | - |  |
| [GradientText](https://www.reactbits.dev/text-animations/gradient-text) | Living gradients inside your text: a sliding sweep, a drifting mesh or a swinging conic fan. | - |  |
| [MaskedHeading](https://www.reactbits.dev/text-animations/masked-heading) | A headline with a drifting colour mesh or image showing through, revealed word by word. | gsap@^3.13.0 |  |
| [ParticleText](https://www.reactbits.dev/text-animations/particle-text) | Text assembles from drifting particles that scatter and reform on demand. | - |  |
| [RotatingText](https://www.reactbits.dev/text-animations/rotating-text) | Cycles through multiple phrases with 3D rotate / flip transitions. | motion@^12.23.12 |  |
| [ScrambledText](https://www.reactbits.dev/text-animations/scrambled-text) | Detects cursor position and applies a distortion effect to text. | gsap@^3.13.0 |  |
| [ScrollFloat](https://www.reactbits.dev/text-animations/scroll-float) | Text gently floats / parallax shifts on scroll. | gsap@^3.13.0 |  |
| [ScrollReveal](https://www.reactbits.dev/text-animations/scroll-reveal) | Text gently unblurs and reveals on scroll. | gsap@^3.13.0 |  |
| [ScrollVelocity](https://www.reactbits.dev/text-animations/scroll-velocity) | Text marquee animatio - speed and distortion scale with user's scroll velocity. | motion@^12.23.12 |  |
| [ShinyText](https://www.reactbits.dev/text-animations/shiny-text) | A sheen of light that sweeps across text, from soft bands to chrome-like reflections. | - |  |
| [Shuffle](https://www.reactbits.dev/text-animations/shuffle) | Animated text reveal where characters shuffle before settling. | gsap@^3.13.0, @gsap/react@^2.1.2 |  |
| [SplitFlapText](https://www.reactbits.dev/text-animations/split-flap-text) | Mechanical split-flap departure board that clacks through to each new phrase. | - |  |
| [SplitText](https://www.reactbits.dev/text-animations/split-text) | Splits text into characters / words for staggered entrance animation. | gsap@^3.13.0, @gsap/react@^2.1.2 |  |
| [StrokeText](https://www.reactbits.dev/text-animations/stroke-text) | Outlined letterforms draw themselves on, then flood with fill. | gsap@^3.13.0 |  |
| [TechText](https://www.reactbits.dev/text-animations/tech-text) | A wordmark whose letters turn into dashed vector paths under the cursor. | - |  |
| [TextCursor](https://www.reactbits.dev/text-animations/text-cursor) | Text or emoji that trails your cursor as stamped copies, a following chain or a ribbon of letters. | - |  |
| [TextLoop](https://www.reactbits.dev/text-animations/text-loop) | A seamless text marquee that flows along curved SVG paths. | gsap@^3.13.0 |  |
| [TextPressure](https://www.reactbits.dev/text-animations/text-pressure) | Characters scale / warp interactively based on pointer pressure zone. | - |  |
| [TextType](https://www.reactbits.dev/text-animations/text-type) | Typewriter effect with blinking cursor and adjustable typing cadence. | gsap@^3.13.0 |  |
| [TrueFocus](https://www.reactbits.dev/text-animations/true-focus) | Applies dynamic blur / clarity based over a series of words in order. | motion@^12.23.12 |  |
| [VariableProximity](https://www.reactbits.dev/text-animations/variable-proximity) | Letter styling changes continuously with pointer distance mapping. | - |  |
| [WarpText](https://www.reactbits.dev/text-animations/warp-text) | WebGL warp that bends and refracts the text around the pointer. | ogl@^1.0.11 |  |

## Uncategorized (1)

| 이름 | 설명 | 의존성 | 변형 |
|---|---|---|---|
| EvilEye | Procedural evil eye shader with animated iris, slit pupil, and fiery outer glow. | ogl@^1.0.11 |  |

## Sounds (201)

효과음 모듈. 변형은 JS·TS 두 가지(`https://reactbits.dev/r/<Name>-JS`, `-TS`). 재생 엔진은 `SoundEngine`.

`SoundAdvance` `SoundAnvil` `SoundAppear` `SoundArrive` `SoundAscent` `SoundAurora` `SoundBackdraft` `SoundBalloon` `SoundBanner` `SoundBead` `SoundBitflip` `SoundBloom` `SoundBlop` `SoundBoop` `SoundBraam` `SoundBreeze` `SoundBubble` `SoundBurble` `SoundCallout` `SoundCalm` `SoundCaption` `SoundCheck` `SoundChiclet` `SoundChime` `SoundCircuit` `SoundClasp` `SoundClockwork` `SoundCoin` `SoundConfetti` `SoundCork` `SoundCorrupt` `SoundCountdown` `SoundCounter` `SoundCrest` `SoundCrystal` `SoundCue` `SoundCushion` `SoundData` `SoundDawn` `SoundDaylight` `SoundDeep` `SoundDescent` `SoundDew` `SoundDing` `SoundDip` `SoundDispatch` `SoundDissolve` `SoundDistant` `SoundDive` `SoundDot` `SoundDownlink` `SoundDrawer` `SoundDread` `SoundDrift` `SoundDrizzle` `SoundDusk` `SoundEllipsis` `SoundEmber` `SoundEmblem` `SoundEngine` `SoundEnigma` `SoundEnter` `SoundErase` `SoundExhale` `SoundFall` `SoundFelt` `SoundFill` `SoundFinale` `SoundFizz` `SoundFlick` `SoundFocus` `SoundFold` `SoundGale` `SoundGlide` `SoundGlimmer` `SoundGlint` `SoundGlow` `SoundGravity` `SoundGust` `SoundHalo` `SoundHaze` `SoundHeart` `SoundHeartbeat` `SoundHerald` `SoundHighland` `SoundHint` `SoundHold` `SoundHover` `SoundHuddle` `SoundInhale` `SoundKeycap` `SoundLantern` `SoundLeaf` `SoundLevel` `SoundLift` `SoundMarble` `SoundMark` `SoundNebula` `SoundNib` `SoundNightfall` `SoundNocturne` `SoundNotch` `SoundNudge` `SoundOrbit` `SoundPass` `SoundPebble` `SoundPetal` `SoundPickup` `SoundPing` `SoundPixel` `SoundPlace` `SoundPluck` `SoundPlug` `SoundPlunge` `SoundPlush` `SoundPopover` `SoundPortal` `SoundPuff` `SoundPulse` `SoundPunchline` `SoundQuake` `SoundRebound` `SoundReceipt` `SoundRelease` `SoundRetreat` `SoundReveal` `SoundRewind` `SoundRipple` `SoundRocker` `SoundRoll` `SoundScramble` `SoundSeal` `SoundSecond` `SoundSettle` `SoundShake` `SoundShimmer` `SoundShrug` `SoundShuffle` `SoundShutter` `SoundSignal` `SoundSilk` `SoundSink` `SoundSiren` `SoundSkip` `SoundSlam` `SoundSlide` `SoundSlowdown` `SoundSnap` `SoundSnow` `SoundSpark` `SoundSpin` `SoundSpiral` `SoundSpring` `SoundSprout` `SoundSqueak` `SoundStack` `SoundStalk` `SoundStamp` `SoundStardust` `SoundStrain` `SoundStreak` `SoundStroke` `SoundStudio` `SoundSummit` `SoundSuspense` `SoundSweep` `SoundSwell` `SoundSwish` `SoundSwoop` `SoundTab` `SoundTally` `SoundThock` `SoundThrottle` `SoundThunder` `SoundTickertape` `SoundTide` `SoundTimber` `SoundTine` `SoundTink` `SoundTracking` `SoundTreasure` `SoundTwin` `SoundUnclasp` `SoundUndo` `SoundUnease` `SoundUnfold` `SoundUnplug` `SoundUpgrade` `SoundUplift` `SoundUplink` `SoundUpswing` `SoundVanish` `SoundVelvet` `SoundVerdict` `SoundWand` `SoundWhip` `SoundWink` `SoundWipe` `SoundWrap` `SoundZap` `SoundZoom`
