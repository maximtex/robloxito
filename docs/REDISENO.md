# Rediseño: simulador de combate automático

Documento de trabajo del rediseño (fases 1 y 2): qué hay en el proyecto, qué se cambia y
cómo encaja todo. Se actualiza al terminar cada fase.

## 1. Auditoría (estado de partida, commit 24bccd4)

### Arquitectura
- Rojo: `src/server` (servicios que arranca `init.server.luau` con `safeStart`),
  `src/client` (controladores que arranca `init.client.luau`), `src/shared` (configuración y
  lógica pura que usan los dos). Un único DataStore (`SaveService`) y atributos del Player para
  replicar al cliente (`PlayerDataService.replicate`). Remotes con nombre en
  `Constants.Remotes` (los crea `RemoteService`).
- Pruebas fuera de Roblox: `python tests/run_tests.py <batería>` monta el código real de
  `src/` con un entorno simulado.

### Combate (antes del rediseño)
- **Dos caminos de disparo duplicados**, cada uno con su fórmula:
  - `CombatService`: un disparo por clic/F (cadencia 0.25 s), daño
    `CombatMath.playerDamage(LaserPower, mascotas) × 0.5`.
  - `PetCombatService`: tras el primer golpe, el servidor dispara solo un "PlayerLaser"
    cada 0.55 s (−0.022 s por nivel de Cadencia) con daño `6 + 4·LaserPower`, y las
    mascotas equipadas golpean al mismo objetivo cada 0.65 s.
- El limitador del servidor descarta disparos al mantener el clic (cuenta también los
  rechazados) y la mejora de Cadencia no afecta al disparo manual.
- Enemigos: una sola IA para todos (`EnemyService`, bucle cada 0.15 s) con estados Idle,
  Chase, Attack, Return y Dead. Jefes: golpe, golpe de área (Slam) y furia; antes de esta
  rama no se movían de su arena.

### Economía
- **Energía ⚡**: la producen los núcleos (`EnergyService`); paga la Resonancia del Cristal
  (`GeneratorPower`, requisito del renacimiento), huevos, zonas y núcleos.
- **Dinero 💰**: lo sueltan los enemigos (cada golpe y al morir); paga la Tienda de Láser.
- Ritmo medido con un jugador activo: ~700 💰/min en el Bosque con el láser inicial,
  ~2 500 en el Valle y ~7 000 en la Caldera.

### Huevos y mascotas
- Huevos: `EggConfig`, `EggLogic`, `PetService.purchaseEgg`, el jardín del mundo
  (`EggStandService`), el panel y la animación de incubar (`PetController`),
  `EggShrineAnimator`, `RevealGate`, el pase `TripleHatch`. Dependen de ellos: la diaria
  `DailyEggs`, el paso "Pet" del tutorial, el premio del día 7 y los códigos con `Pet`.
- Mascotas: `PetConfig` (24 especies, rarezas ×1.1 a ×6), `PetMath` (multiplicador aditivo),
  `PetService` (inventario, equipar, evolucionar, `grantPet`), `PetCombatService` (golpes de
  las equipadas), `PetFollower`/`PetModelBuilder` (cliente). El multiplicador sube la
  energía y la mitad de su bonificación el daño.
- Error encontrado: al cargar una partida, `SaveService.sanitize` partía de los datos vacíos,
  que ya traen la mascota inicial "p1", así que cada carga añadía otra y la equipaba primero.

### Mapas y progresión
- Bosque (por defecto) → Valle Morado (2 500 ⚡) → Caldera de Brasas (25 000 ⚡), unidos por
  portales de cristal (`ZoneService`); se cruza andando al desbloquear.
- Renacimiento: pide nivel de Resonancia `min(50, 15 + 5·n)`; da fichas y multiplicadores de
  energía, botín y daño; reinicia la energía y la Resonancia.
- Misiones, diarias y logros pagan energía; los premios diarios, cofres y códigos también.
- `GeneratorService` (santuario del cristal) y `CoreShrineService` (altares de núcleos) están
  desactivados en `init.server.luau`: no se tocan sin preguntar (ni cambiarían el mapa verde).

### Mapa verde (Bosque): objetos físicos que NO se modifican
Todo lo construye código al arrancar, en posiciones fijas:
- Terreno plano y suelo de bloques con sus caminos (`WorldService.buildFlatTerrain`,
  `StudWorld.buildFloor`, trazado en `StudFloor.Zones.Forest`).
- Muros del perímetro y la puerta (`StudWorld.buildWalls`), límite invisible
  (`LandscapeService`).
- Árboles, espantapájaros, calabazas, setas y hierba (`WorldService.buildForestDetails`, con
  semilla fija y círculos reservados: mover cualquier cosa reservada recoloca todo).
- Decoración de Navidad (`ChristmasDecor`, `SeasonConfig.ForestDecor`).
- Puestos del pueblo, evolucionador y cofre «RECLAMAR» (`VillageService`).
- Jardín de los huevos: altar, pedestales y expositor arcoíris (`EggStandService`).
- Tablas de clasificación (`LeaderboardService`), cofres escondidos (`ChestService`),
  portal (`ZoneService`), punto de aparición (`SpawnService`).
- Del archivo del lugar: `ReplicatedStorage.PetModels` (Haxigator) y los modelos sueltos
  que hay bajo el mapa.

Regla del rediseño: no se cambia ninguna posición, tamaño ni pieza de estos constructores
ni nada de lo que reserva sitio en el mapa. Lo nuevo reutiliza lo que ya existe (los
pedestales venden mascotas, el puesto del láser es la Armería, las arenas de los jefes
siguen donde están).

## 2. Arquitectura del rediseño

### Monedas
| Moneda | Se gana | Se gasta |
|---|---|---|
| 💰 Dinero | Enemigos (cada golpe y al morir), jefes | Armas y sus mejoras, mejoras de la Armería, mascotas del jardín |
| ⚡ Energía | Núcleos (producción), misiones, cofres, premios, jefes | Resonancia del Cristal (renacer), zonas, núcleos |

Las mascotas multiplican la energía (100 % de su bonificación), el daño (50 %) y el dinero
(50 %).

### Armas (fase 3)
- `WeaponConfig` + `WeaponLogic` (puras) y `WeaponService` (servidor). Siete armas con daño,
  cadencia, alcance, proyectil y efecto propios (área, salto entre enemigos, ralentizar):
  Láser Básico, Bláster de Plasma, Arco de Espinas (jefe del Bosque), Cañón Cristalino
  (Valle), Prisma de Amatista (jefe del Valle), Cañón del Vacío (Caldera), Corazón de Magma
  (jefe de la Caldera).
- Cada arma tiene niveles (+15 % de daño por nivel, hasta 25). La antigua "Potencia del
  Láser" pasa a ser el nivel del Láser Básico. La Cadencia es global (todas las armas).
- La Armería es el puesto "Mejorar Láser" del pueblo (mismo sitio y modelo; cambia su
  nombre) y también se abre con la tecla L o el botón del menú.
- Precios con el ritmo real: Plasma 4 000 (~6 min en el Bosque), Cañón Cristalino 25 000
  (~10 min en el Valle), Cañón del Vacío 120 000 (~15 min en la Caldera).

### Combate automático (fase 5)
- Un único camino de disparo en el servidor (`PetCombatService`): cada jugador tiene un
  objetivo; si no lo tiene, el más cercano a tiro de su arma (con comprobación de altura).
  Se mantiene hasta que muere, sale de alcance o el jugador elige otro con un clic. Dispara
  con la cadencia de su arma y aplica su efecto. Las mascotas atacan al mismo objetivo.
- El clic ya no hace daño propio: elige el objetivo. F o el botón "Disparar" encienden y
  apagan el disparo automático.

### Mascotas sin huevos (fase 4)
- Los pedestales del jardín venden una mascota fija cada uno (compra directa con dinero):
  Seta Saltarina, Zorro de Musgo, Búho Lunar y, en el expositor arcoíris, el Cervatillo
  Esmeralda. Sin azar, sin incubar.
- Cada jefe regala su mascota de combate la primera vez (Zorrito de Cuarzo, Tortuga
  Cristalina, Dragón de Amatista) y luego a veces otra copia (para evolucionar).
- El Haxigator se sigue vendiendo por Robux en el altar.
- Se retiran: comprar e incubar huevos, el panel de huevos, la diaria `DailyEggs` y el pase
  `TripleHatch`. Las mascotas guardadas no se tocan.

### Jefes (fase 6)
- Máquina de estados propia (`EnemyService.updateBoss`): Patrulla, Persecución (con
  `PathfindingService` si algo se interpone), Ocupado (ataque anunciado), Descanso y Regreso.
  Nunca salen de su territorio; mantienen el objetivo unos segundos.
- Identidad: Guardián del Bosque (golpe de área + raíces que ralentizan), Coloso de Amatista
  (golpe de área + embestidas), Titán de la Caldera (golpe de área + saltos + bolas de fuego).

### Progresión entre mapas (fase 7)
- Valle: derrotar al Guardián del Bosque + 2 500 ⚡. Caldera: derrotar al Coloso + 25 000 ⚡.
- Los jefes derrotados se guardan (`Bosses`); quien ya tenía una zona la conserva.

### Renacimiento
- Requisito sin cambios (nivel de Resonancia). Se reinicia: energía, dinero, Resonancia y
  niveles de las armas. Se conserva: armas compradas y la equipada, mascotas, zonas, jefes
  derrotados, mejoras de la Armería, núcleos, misiones y la tienda de fichas.

### Guardado
- Esquema v8: `Weapons` (`WeaponLogic.serialize`) y `Bosses`. Los registros antiguos cargan
  con el láser inicial (con el nivel de la antigua Potencia del Láser) y sin jefes.
